// AirDrop2X — make AirDrop deliver files straight into a folder of your choosing.
// Copyright (C) 2026 Dr. Karim Badawi, Techtag GmbH
//
// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any later
// version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
// PARTICULAR PURPOSE. See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with
// this program. If not, see <https://www.gnu.org/licenses/>.

import AppKit

/// An iOS-style toggle: green track when on, grey when off, white knob. Drawn by hand because a
/// stock NSSwitch inside a menu renders in its inactive (grey) look and follows the accent color.
final class ToggleSwitch: NSControl {
    var isOn = false { didSet { needsDisplay = true } }
    private let trackSize = NSSize(width: 34, height: 20)

    override var intrinsicContentSize: NSSize { trackSize }
    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let track = NSRect(x: 0, y: (bounds.height - trackSize.height) / 2, width: trackSize.width, height: trackSize.height)
        let onColor = NSColor.systemGreen
        let offColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor.white.withAlphaComponent(0.25) : NSColor.black.withAlphaComponent(0.16)
        }
        var fill = isOn ? onColor : offColor
        if !isEnabled { fill = fill.withAlphaComponent(0.35) }
        fill.setFill()
        NSBezierPath(roundedRect: track, xRadius: track.height / 2, yRadius: track.height / 2).fill()

        let inset: CGFloat = 2
        let knobDiameter = track.height - inset * 2
        let knobX = isOn ? track.maxX - inset - knobDiameter : track.minX + inset
        let knob = NSRect(x: knobX, y: track.minY + inset, width: knobDiameter, height: knobDiameter)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 1.5
        shadow.set()
        (isEnabled ? NSColor.white : NSColor.white.withAlphaComponent(0.7)).setFill()
        NSBezierPath(ovalIn: knob).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        isOn.toggle()
        sendAction(action, to: target)
    }
}

/// A menu row with a label on the left and a toggle switch flush right.
final class SwitchMenuItemView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let toggle = ToggleSwitch()
    var onChange: ((Bool) -> Void)?

    init(title: String, isOn: Bool, isEnabled: Bool, width: CGFloat = 270) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 30))
        autoresizingMask = [.width]   // the menu stretches the row to its full width, so the switch sits at the right edge
        label.stringValue = title
        label.font = NSFont.menuFont(ofSize: 0)
        label.textColor = isEnabled ? .labelColor : .disabledControlTextColor
        toggle.isOn = isOn
        toggle.isEnabled = isEnabled
        toggle.target = self
        toggle.action = #selector(toggled)
        for view in [label, toggle] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            toggle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            toggle.centerYAnchor.constraint(equalTo: centerYAnchor),
            toggle.widthAnchor.constraint(equalToConstant: 34),
            toggle.heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    /// Clicking anywhere on the row flips the switch too.
    override func mouseDown(with event: NSEvent) {
        guard toggle.isEnabled else { return }
        toggle.isOn.toggle()
        toggled()
    }

    @objc private func toggled() {
        onChange?(toggle.isOn)   // the menu stays open; the delegate refreshes the rows in place
    }
}

/// A menu row showing the current destination with an ✕ button at the right to clear it.
final class DestinationMenuItemView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let clearButton = NSButton()
    var onClear: (() -> Void)?

    init(path: String, width: CGFloat = 270) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 26))
        autoresizingMask = [.width]
        label.stringValue = "Destination: \(path)"
        label.font = NSFont.menuFont(ofSize: 0)
        label.textColor = .secondaryLabelColor   // informational line, like the status text above it
        label.lineBreakMode = .byTruncatingMiddle
        label.toolTip = path
        clearButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Clear destination")
        clearButton.isBordered = false
        clearButton.imagePosition = .imageOnly
        clearButton.contentTintColor = .secondaryLabelColor
        clearButton.toolTip = "Clear the destination"
        clearButton.target = self
        clearButton.action = #selector(clear)
        for view in [label, clearButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: clearButton.leadingAnchor, constant: -8),
            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 18),
            clearButton.heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func clear() { onClear?() }
}
