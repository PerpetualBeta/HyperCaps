import AppKit

/// A macOS-style HUD that briefly shows Caps Lock on/off state in the centre of the screen.
@MainActor
final class CapsLockHUD {
    static let shared = CapsLockHUD()

    private var window: NSPanel?
    private var hideTask: DispatchWorkItem?

    func show(enabled: Bool) {
        hideTask?.cancel()

        let size: CGFloat = 160
        let panel = makePanel(size: size)
        let content = makeContent(size: size, enabled: enabled)
        panel.contentView = content

        // Centre on the main screen
        if let screen = NSScreen.main {
            let screenFrame = screen.frame
            let x = screenFrame.midX - size / 2
            let y = screenFrame.midY - size / 2
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.alphaValue = 1
        panel.orderFrontRegardless()
        window = panel

        // Fade out after 1.5 seconds
        let task = DispatchWorkItem { [weak self] in
            guard let self, let w = self.window else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.4
                w.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                w.orderOut(nil)
                Task { @MainActor in self?.window = nil }
            })
        }
        hideTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: task)
    }

    private func makePanel(size: CGFloat) -> NSPanel {
        if let existing = window {
            return existing
        }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        return panel
    }

    private func makeContent(size: CGFloat, enabled: Bool) -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: size, height: size))

        // Dark rounded background
        let bg = RoundedBackgroundView(frame: container.bounds)
        bg.autoresizingMask = [.width, .height]
        container.addSubview(bg)

        // Caps Lock icon
        let symbolName = enabled ? "capslock.fill" : "capslock"
        let iconSize: CGFloat = 64
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Caps Lock") {
            let config = NSImage.SymbolConfiguration(pointSize: iconSize, weight: .light)
            let configured = image.withSymbolConfiguration(config) ?? image
            let imageView = NSImageView(frame: NSRect(
                x: (size - iconSize) / 2,
                y: size / 2 - iconSize / 2 + 14,
                width: iconSize,
                height: iconSize
            ))
            imageView.image = configured
            imageView.contentTintColor = .white
            container.addSubview(imageView)
        }

        // Label
        let label = NSTextField(labelWithString: enabled ? "Caps Lock On" : "Caps Lock Off")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 18, width: size, height: 20)
        container.addSubview(label)

        return container
    }
}

// MARK: - Rounded background

private class RoundedBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 20, yRadius: 20)
        NSColor(white: 0.08, alpha: 0.85).setFill()
        path.fill()
    }
}
