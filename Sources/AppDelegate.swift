import AppKit
import ApplicationServices
import SwiftUI
import ServiceManagement

// MARK: - App Delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private var statusItem: NSStatusItem!
    let engine = HyperCapsEngine()
    let updateChecker = JorvikUpdateChecker(repoName: "HyperCaps")

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
        NSApp.setActivationPolicy(.accessory)

        HyperCapsEngine.installCleanupHandlers()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon()
        JorvikMenuBarPill.apply(to: statusItem.button!)
        updateChecker.checkOnSchedule()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(appearanceChanged),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )

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

    @objc private func appearanceChanged() {
        if let button = statusItem.button {
            JorvikMenuBarPill.refresh(on: button)
        }
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

    private func updateIcon() {
        let symbolName = engine.isActive ? "capslock.fill" : "capslock"
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "HyperCaps") {
            image.isTemplate = true
            statusItem.button?.image = image
        } else {
            statusItem.button?.title = "⇪"
        }
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
