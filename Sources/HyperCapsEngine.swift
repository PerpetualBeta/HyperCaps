import AppKit
import ApplicationServices
import IOKit
import IOKit.hid

// MARK: - Module-level state for C-compatible CGEvent tap callback

private var _hyperActive = false
private var _keyPressedDuringHyper = false
private var _hyperEventTap: CFMachPort?
private var _hyperModifiers: CGEventFlags = [.maskCommand, .maskControl, .maskShift, .maskAlternate]
private var _shiftHeldWhenHyperPressed = false
private var _onShiftTap: (() -> Void)?
private let _f18KeyCode: Int64 = 79

// MARK: - Cleanup helpers (module-level for C function pointer compatibility)

private var _cleanupPath: UnsafeMutablePointer<CChar>!
private var _cleanupArg0: UnsafeMutablePointer<CChar>!
private var _cleanupArg1: UnsafeMutablePointer<CChar>!
private var _cleanupArg2: UnsafeMutablePointer<CChar>!
private var _cleanupArg3: UnsafeMutablePointer<CChar>!

private func _hyperCapsInitCleanupStrings() {
    _cleanupPath = strdup("/usr/bin/hidutil")
    _cleanupArg0 = strdup("hidutil")
    _cleanupArg1 = strdup("property")
    _cleanupArg2 = strdup("--set")
    _cleanupArg3 = strdup(#"{"UserKeyMapping":[]}"#)
}

private func _hyperCapsClearHIDRemap() {
    guard _cleanupPath != nil else { return }
    var pid: pid_t = 0
    var argv: [UnsafeMutablePointer<CChar>?] = [
        _cleanupArg0, _cleanupArg1, _cleanupArg2, _cleanupArg3, nil
    ]
    var fileActions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&fileActions)
    posix_spawn_file_actions_addopen(&fileActions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0)
    posix_spawn_file_actions_addopen(&fileActions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)

    let result = posix_spawn(&pid, _cleanupPath, &fileActions, nil, &argv, environ)
    posix_spawn_file_actions_destroy(&fileActions)

    if result == 0 {
        var status: Int32 = 0
        waitpid(pid, &status, 0)
    }
}

// MARK: - CGEvent tap callback

private func hyperKeyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // Auto-re-enable if macOS disabled the tap
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = _hyperEventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passRetained(event)
    }

    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

    // --- F18 keyDown: activate hyper mode ---
    if type == .keyDown && keyCode == _f18KeyCode {
        _hyperActive = true
        _keyPressedDuringHyper = false
        _shiftHeldWhenHyperPressed = event.flags.contains(.maskShift)
        return nil // consume
    }

    // --- F18 keyUp: deactivate hyper mode ---
    if type == .keyUp && keyCode == _f18KeyCode {
        let wasShift = _shiftHeldWhenHyperPressed
        let hadKeyPress = _keyPressedDuringHyper
        _hyperActive = false
        _shiftHeldWhenHyperPressed = false
        _keyPressedDuringHyper = false

        if wasShift && !hadKeyPress {
            // Shift + CapsLock bare tap → toggle Caps Lock
            DispatchQueue.main.async { _onShiftTap?() }
        }
        // Bare tap without shift: do nothing (by design)
        return nil // consume
    }

    // --- flagsChanged for F18: consume to prevent phantom modifier events ---
    if type == .flagsChanged && keyCode == _f18KeyCode {
        return nil // consume
    }

    // --- Any other key while hyper is active: inject modifier flags ---
    if _hyperActive && type == .keyDown {
        _keyPressedDuringHyper = true
        event.flags = event.flags.union(_hyperModifiers)
        return Unmanaged.passRetained(event)
    }

    if _hyperActive && type == .keyUp {
        event.flags = event.flags.union(_hyperModifiers)
        return Unmanaged.passRetained(event)
    }

    // Pass everything else through unchanged
    return Unmanaged.passRetained(event)
}

// MARK: - HyperCapsEngine

@MainActor
@Observable
final class HyperCapsEngine {
    var isActive: Bool = false
    var capsLockEnabled: Bool = false
    var permissionGranted: Bool = false

    private var eventTap: CFMachPort?
    private var permissionTimer: Timer?

    // MARK: - System remap detection

    /// Returns true if macOS System Settings has remapped Caps Lock to something
    /// other than Caps Lock (e.g. Escape, No Action, Control), which would prevent
    /// HyperCaps from intercepting it.
    static func capsLockHasSystemRemap() -> Bool {
        let capsLockUsage = 0x700000039
        guard let keys = CFPreferencesCopyKeyList(
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        ) as? [String] else { return false }

        for key in keys where key.hasPrefix("com.apple.keyboard.modifiermapping.") {
            guard let value = CFPreferencesCopyValue(
                key as CFString,
                kCFPreferencesAnyApplication,
                kCFPreferencesCurrentUser,
                kCFPreferencesCurrentHost
            ), let mappings = value as? [[String: Any]] else { continue }

            for mapping in mappings {
                if let src = mapping["HIDKeyboardModifierMappingSrc"] as? Int,
                   let dst = mapping["HIDKeyboardModifierMappingDst"] as? Int,
                   src == capsLockUsage,
                   dst != capsLockUsage {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Public API

    func start(modifiers: CGEventFlags) async {
        guard !isActive else { return }

        // Clear any stale hidutil mapping from a previous crash
        await removeHIDRemap()
        await installHIDRemap()

        _hyperModifiers = modifiers
        _onShiftTap = { [weak self] in
            Task { @MainActor in
                self?.toggleCapsLock()
            }
        }

        if tryCreateEventTap() {
            isActive = true
        }
    }

    func stop() async {
        isActive = false
        // Disable the tap synchronously first so input is released immediately
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        eventTap = nil
        _hyperEventTap = nil
        _hyperActive = false
        _keyPressedDuringHyper = false
        _shiftHeldWhenHyperPressed = false
        await removeHIDRemap()
    }

    func updateModifiers(_ modifiers: CGEventFlags) {
        _hyperModifiers = modifiers
    }

    func requestPermissionAndStart(modifiers: CGEventFlags) async {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        permissionGranted = trusted

        if !trusted {
            // Suspend until the user grants Accessibility permission
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
                    if AXIsProcessTrusted() {
                        Task { @MainActor in self?.permissionGranted = true }
                        timer.invalidate()
                        continuation.resume()
                    }
                }
            }
        }

        await start(modifiers: modifiers)
    }

    // MARK: - Layer 1: hidutil key remap

    private func installHIDRemap() async {
        await runHidutil(#"{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x70000006D}]}"#)
    }

    private func removeHIDRemap() async {
        await runHidutil(#"{"UserKeyMapping":[]}"#)
    }

    private func runHidutil(_ json: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
                process.arguments = ["property", "--set", json]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                try? process.run()

                // Kill hidutil if it hangs for more than 5 seconds
                DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                    if process.isRunning { process.terminate() }
                }
                process.waitUntilExit()
                continuation.resume()
            }
        }
    }

    // MARK: - Layer 2: CGEvent tap

    private func tryCreateEventTap() -> Bool {
        if eventTap != nil { return true }

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
                              | (1 << CGEventType.keyUp.rawValue)
                              | (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hyperKeyTapCallback,
            userInfo: nil
        ) else {
            return false
        }

        eventTap = tap
        _hyperEventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    // MARK: - Layer 3: IOKit Caps Lock toggle

    func toggleCapsLock() {
        capsLockEnabled.toggle()
        setCapsLock(enabled: capsLockEnabled)
        CapsLockHUD.shared.show(enabled: capsLockEnabled)
    }

    private func setCapsLock(enabled: Bool) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
            IOServiceMatching(kIOHIDSystemClass))
        guard service != IO_OBJECT_NULL else { return }

        var connect: io_connect_t = 0
        let kr = IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connect)
        IOObjectRelease(service)
        guard kr == KERN_SUCCESS else { return }

        IOHIDSetModifierLockState(connect, Int32(kIOHIDCapsLockState), enabled)
        IOServiceClose(connect)
    }

    // MARK: - Crash safety

    static func installCleanupHandlers() {
        _hyperCapsInitCleanupStrings()

        atexit {
            _hyperCapsClearHIDRemap()
        }

        let handler: @convention(c) (Int32) -> Void = { _ in
            _hyperCapsClearHIDRemap()
            _exit(0)
        }
        signal(SIGTERM, handler)
        signal(SIGINT, handler)
    }
}
