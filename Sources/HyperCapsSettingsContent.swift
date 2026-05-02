import SwiftUI

struct HyperCapsSettingsContent: View {
    let delegate: AppDelegate

    var body: some View {
        Section("Hyper Key Modifiers") {
            Toggle("Command (⌘)", isOn: Binding(
                get: { delegate.useCommand },
                set: { newValue in
                    if newValue || hasOtherModifier(excluding: "command") {
                        delegate.useCommand = newValue
                    }
                }
            ))

            Toggle("Control (⌃)", isOn: Binding(
                get: { delegate.useControl },
                set: { newValue in
                    if newValue || hasOtherModifier(excluding: "control") {
                        delegate.useControl = newValue
                    }
                }
            ))

            Toggle("Option (⌥)", isOn: Binding(
                get: { delegate.useOption },
                set: { newValue in
                    if newValue || hasOtherModifier(excluding: "option") {
                        delegate.useOption = newValue
                    }
                }
            ))

            Toggle("Shift (⇧)", isOn: Binding(
                get: { delegate.useShift },
                set: { newValue in
                    if newValue || hasOtherModifier(excluding: "shift") {
                        delegate.useShift = newValue
                    }
                }
            ))

            Text("At least one modifier must be selected.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Section("Permissions") {
            HStack {
                Text("Accessibility")
                Spacer()
                if AXIsProcessTrusted() {
                    Label("Granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                } else {
                    Button("Grant Access") {
                        let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
                        AXIsProcessTrustedWithOptions(opts)
                    }
                    .font(.caption)
                }
            }
        }

        MenuBarPillSettings { delegate.updateIcon() }
    }

    private func hasOtherModifier(excluding: String) -> Bool {
        var count = 0
        if excluding != "command" && delegate.useCommand { count += 1 }
        if excluding != "control" && delegate.useControl { count += 1 }
        if excluding != "option" && delegate.useOption { count += 1 }
        if excluding != "shift" && delegate.useShift { count += 1 }
        return count > 0
    }
}
