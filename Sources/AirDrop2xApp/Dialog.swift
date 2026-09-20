import AppKit

/// A centered dialog: symbol on top, bold title, explanatory text, buttons. Used instead of NSAlert,
/// whose macOS 26 layout pins the icon to the top-left corner.
enum Dialog {
    /// Shows the dialog modally. Returns the index of the clicked button (0 = first).
    @discardableResult
    static func show(title: String, text: String, symbol: String = "exclamationmark.triangle.fill",
                     tint: NSColor = .systemOrange, buttons: [String] = ["OK"]) -> Int {
        show(title: title, text: text, image: squareSymbolIcon(symbol, canvas: 72, pointSize: 50, tint: tint), buttons: buttons)
    }

    /// Same dialog with an arbitrary image on top (used by About with the app icon).
    @discardableResult
    static func show(title: String, text: String, image: NSImage?, buttons: [String] = ["OK"]) -> Int {
        let width: CGFloat = 440
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 200),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.isReleasedWhenClosed = false

        let icon = NSImageView(image: image ?? NSImage())
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.setContentHuggingPriority(.required, for: .vertical)

        let titleLabel = NSTextField(wrappingLabelWithString: title)
        titleLabel.font = .boldSystemFont(ofSize: 15)
        titleLabel.alignment = .center

        let textLabel = NSTextField(wrappingLabelWithString: text)
        textLabel.font = .systemFont(ofSize: 13)
        textLabel.textColor = .secondaryLabelColor
        textLabel.alignment = .center

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 12
        var result = 0
        for (index, name) in buttons.enumerated() {
            let button = NSButton(title: name, target: nil, action: nil)
            button.bezelStyle = .rounded
            button.keyEquivalent = index == buttons.count - 1 ? "\r" : (index == 0 && buttons.count > 1 ? "\u{1b}" : "")
            button.tag = index
            let handler = ButtonHandler { result = index; NSApp.stopModal() }
            button.target = handler
            button.action = #selector(ButtonHandler.fire)
            objc_setAssociatedObject(button, "handler", handler, .OBJC_ASSOCIATION_RETAIN)
            buttonRow.addArrangedSubview(button)
        }

        let stack = NSStackView(views: [icon, titleLabel, textLabel, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.setCustomSpacing(20, after: textLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = window.contentView!
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            icon.widthAnchor.constraint(equalToConstant: 72),
            icon.heightAnchor.constraint(equalToConstant: 72),
            titleLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            textLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        content.layoutSubtreeIfNeeded()
        let height = stack.fittingSize.height + 48
        window.setContentSize(NSSize(width: width, height: height))
        window.center()

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: window)
        window.orderOut(nil)
        return result
    }

    private final class ButtonHandler: NSObject {
        let block: () -> Void
        init(_ block: @escaping () -> Void) { self.block = block }
        @objc func fire() { block() }
    }

    /// An SF Symbol drawn onto a square canvas and centered on its visible pixels.
    static func squareSymbolIcon(_ name: String, canvas: CGFloat, pointSize: CGFloat, tint: NSColor) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [tint, .tertiaryLabelColor]))
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return nil }
        let scale: CGFloat = 2
        let w = Int(symbol.size.width * scale), h = Int(symbol.size.height * scale)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return symbol }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        symbol.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        var minX = w, maxX = -1, minY = h, maxY = -1
        for y in 0..<h { for x in 0..<w where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        guard maxX >= 0 else { return symbol }
        let visible = NSRect(x: CGFloat(minX) / scale, y: CGFloat(h - 1 - maxY) / scale,
                             width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
        return NSImage(size: NSSize(width: canvas, height: canvas), flipped: false) { _ in
            symbol.draw(in: NSRect(origin: NSPoint(x: canvas / 2 - visible.midX, y: canvas / 2 - visible.midY), size: symbol.size))
            return true
        }
    }
}
