import AppKit
import ApplicationServices
import SwiftUI
import ServiceManagement
import Sparkle

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    let engine = HyperCapsEngine()
    let updateChecker = JorvikUpdateChecker(repoName: "HyperCaps")
    let sparkleUserDriverDelegate = HyperCapsUserDriverDelegate()
    lazy var sparkleUpdater = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: sparkleUserDriverDelegate
    )

    // Settings (persisted via UserDefaults)
    var useCommand: Bool {
        get { UserDefaults.standard.object(forKey: "useCommand") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "useCommand"); syncModifiers() }
    }
    var useControl: Bool {
        get { UserDefaults.standard.object(forKey: "useControl") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "useControl"); syncModifiers() }
    }
    var useOption: Bool {
        get { UserDefaults.standard.object(forKey: "useOption") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "useOption"); syncModifiers() }
    }
    var useShift: Bool {
        get { UserDefaults.standard.object(forKey: "useShift") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "useShift"); syncModifiers() }
    }

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        migrateLegacyPillColorKey()

        NSApp.setActivationPolicy(.accessory)

        HyperCapsEngine.installCleanupHandlers()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon()
        // Sparkle handles update polling now. JorvikUpdateChecker instance
        // remains because JorvikSettingsView.showWindow still requires one
        // as a parameter, pending JorvikKit retirement (§11.5).
        _ = sparkleUpdater  // forces lazy init so Sparkle starts at launch
        // updateChecker.checkOnSchedule()  // disabled — Sparkle owns this now

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // Check for conflicting system-level Caps Lock remap
        if HyperCapsEngine.capsLockHasSystemRemap() {
            showCapsLockRemapAlert()
        }

        // Start the hyper key engine
        Task {
            await engine.requestPermissionAndStart(modifiers: buildModifiers())
            updateIcon()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { await engine.stop() }
    }

    // One-shot removal of the user-chosen pill colour key from the old design.
    // The new pill uses fixed grey/light colours; the key is dead weight.
    private func migrateLegacyPillColorKey() {
        let migrated = "didMigratePillColorV2"
        if UserDefaults.standard.bool(forKey: migrated) { return }
        UserDefaults.standard.removeObject(forKey: "menuBarPillColor")
        UserDefaults.standard.set(true, forKey: migrated)
    }

    // MARK: - Modifier helpers

    func buildModifiers() -> CGEventFlags {
        var flags: CGEventFlags = []
        if useCommand { flags.insert(.maskCommand) }
        if useControl { flags.insert(.maskControl) }
        if useOption { flags.insert(.maskAlternate) }
        if useShift { flags.insert(.maskShift) }
        // Safety: at least one modifier must be set
        if flags.isEmpty { flags.insert(.maskCommand) }
        return flags
    }

    func syncModifiers() {
        let modifiers = buildModifiers()
        engine.updateModifiers(modifiers)
    }

    func modifierDisplayString() -> String {
        var parts: [String] = []
        if useControl { parts.append("⌃") }
        if useOption { parts.append("⌥") }
        if useShift { parts.append("⇧") }
        if useCommand { parts.append("⌘") }
        return parts.isEmpty ? "⌘" : parts.joined()
    }

    // MARK: - Icon

    func updateIcon() {
        let symbolName = engine.isActive ? "capslock.fill" : "capslock"
        statusItem.button?.image = JorvikMenuBarPill.icon(
            symbolName: symbolName,
            accessibilityDescription: "HyperCaps"
        )
    }

    // MARK: - Dynamic menu (NSMenuDelegate)

    func menuNeedsUpdate(_ menu: NSMenu) {
        updateIcon()

        var actions: [JorvikMenuBuilder.ActionItem] = []

        // Toggle hyper key
        actions.append(JorvikMenuBuilder.ActionItem(
            title: "Hyper Key Active",
            action: #selector(toggleHyperKey),
            target: self,
            state: engine.isActive ? .on : .off
        ))

        // Caps Lock status (informational, non-clickable)
        let capsStatus = engine.capsLockEnabled ? "On" : "Off"
        let capsText = "Caps Lock: \(capsStatus)"
        let capsAttr = NSAttributedString(string: capsText, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor
        ])
        actions.append(JorvikMenuBuilder.ActionItem(
            title: capsText,
            action: #selector(noop),
            target: self,
            isEnabled: false,
            attributedTitle: capsAttr
        ))

        // Current modifier display
        let modStr = "Sends: \(modifierDisplayString()) + key"
        let modAttr = NSAttributedString(string: modStr, attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor
        ])
        actions.append(JorvikMenuBuilder.ActionItem(
            title: modStr,
            action: #selector(noop),
            target: self,
            isEnabled: false,
            attributedTitle: modAttr
        ))

        actions.append(JorvikMenuBuilder.ActionItem(title: "-", action: #selector(noop), target: self))
        actions.append(JorvikMenuBuilder.ActionItem(
            title: "Check for Updates\u{2026}",
            action: #selector(checkForUpdates(_:)),
            target: self
        ))

        let built = JorvikMenuBuilder.buildMenu(
            appName: "HyperCaps",
            aboutAction: #selector(openAbout),
            settingsAction: #selector(openSettings),
            target: self,
            actions: actions
        )

        menu.removeAllItems()
        for item in built.items {
            built.removeItem(item)
            menu.addItem(item)
        }
    }

    // MARK: - Actions

    @objc private func toggleHyperKey() {
        Task {
            if engine.isActive {
                await engine.stop()
            } else {
                await engine.requestPermissionAndStart(modifiers: buildModifiers())
            }
            updateIcon()
        }
    }

    @objc private func noop() {}

    @objc func checkForUpdates(_ sender: Any?) {
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        sparkleUpdater.checkForUpdates(sender)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Caps Lock remap warning

    private func showCapsLockRemapAlert() {
        let alert = NSAlert()
        alert.messageText = "Caps Lock Has Been Remapped"
        alert.informativeText = "macOS System Settings has Caps Lock assigned to a different action. HyperCaps needs Caps Lock set to its default behaviour.\n\nOpen System Settings → Keyboard → Keyboard Shortcuts → Modifier Keys and set Caps Lock back to \"Caps Lock\"."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Keyboard Settings")
        alert.addButton(withTitle: "Dismiss")

        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: - About & Settings

    @objc private func openAbout() {
        JorvikAboutView.showWindow(
            appName: "HyperCaps",
            repoName: "HyperCaps",
            productPage: "utilities/hypercaps"
        )
    }

    @objc private func openSettings() {
        let delegate = self
        JorvikSettingsView.showWindow(
            appName: "HyperCaps",
            updateChecker: updateChecker
        ) {
            HyperCapsSettingsContent(delegate: delegate)
        }
    }
}

/// Keeps Sparkle's update UI visible across the whole session, including
/// when the user switches to another app mid-download. See KB:
/// `conventions/sparkle-integration.md` §6 for the rationale.
final class HyperCapsUserDriverDelegate: NSObject, SPUStandardUserDriverDelegate {
    private var sessionObserver: NSObjectProtocol?
    private var elevatedWindows: [(window: NSWindow, originalLevel: NSWindow.Level)] = []

    func standardUserDriverWillShowModalAlert() {
        bringForward()
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        startFocusGuard()
        bringForward()
    }

    func standardUserDriverWillFinishUpdateSession() {
        stopFocusGuard()
    }

    private func bringForward() {
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        elevateAllWindows()
    }

    private func startFocusGuard() {
        guard sessionObserver == nil else { return }
        sessionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.bringForward()
        }
    }

    private func stopFocusGuard() {
        if let obs = sessionObserver {
            NotificationCenter.default.removeObserver(obs)
            sessionObserver = nil
        }
        for entry in elevatedWindows {
            entry.window.level = entry.originalLevel
        }
        elevatedWindows.removeAll()
    }

    private func elevateAllWindows() {
        for window in NSApp.windows where window.isVisible && window.level == .normal {
            elevatedWindows.append((window, window.level))
            window.level = .floating
        }
    }
}
