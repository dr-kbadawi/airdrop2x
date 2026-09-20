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

import XCTest
import AppKit
import AirDrop2xCore
@testable import AirDrop2xApp

/// Pixel helpers for verifying drawn images.
enum Pixels {
    static func bitmap(_ image: NSImage, scale: CGFloat = 2) -> NSBitmapImageRep {
        let w = Int(image.size.width * scale), h = Int(image.size.height * scale)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// Bounding box of the opaque pixels, or nil when nothing was drawn.
    static func opaqueBounds(_ rep: NSBitmapImageRep) -> NSRect? {
        var minX = rep.pixelsWide, maxX = -1, minY = rep.pixelsHigh, maxY = -1
        for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        guard maxX >= 0 else { return nil }
        return NSRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    static func dominantHue(_ rep: NSBitmapImageRep) -> CGFloat? {
        var hues: [CGFloat] = []
        for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide {
            if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), c.alphaComponent > 0.9, c.saturationComponent > 0.3 { hues.append(c.hueComponent) }
        } }
        guard !hues.isEmpty else { return nil }
        return hues.reduce(0, +) / CGFloat(hues.count)
    }
}

final class StatusGlyphTests: XCTestCase {
    func testSizeAndNotTemplate() {
        let image = StatusGlyph.image(color: .systemGreen)
        XCTAssertEqual(image.size, NSSize(width: 18, height: 20))
        XCTAssertFalse(image.isTemplate, "a colored icon must not be treated as a template")
    }

    func testDrawsSomethingInEachStateColor() {
        for color in [NSColor.systemGreen, .systemOrange, .systemGray] {
            let rep = Pixels.bitmap(StatusGlyph.image(color: color))
            let bounds = Pixels.opaqueBounds(rep)
            XCTAssertNotNil(bounds, "\(color) glyph is empty")
            XCTAssertGreaterThan(bounds!.width, CGFloat(rep.pixelsWide) * 0.6, "glyph should use most of the width")
            XCTAssertGreaterThan(bounds!.height, CGFloat(rep.pixelsHigh) * 0.6)
        }
    }

    func testColorIsApplied() {
        let green = Pixels.dominantHue(Pixels.bitmap(StatusGlyph.image(color: .systemGreen)))!
        let orange = Pixels.dominantHue(Pixels.bitmap(StatusGlyph.image(color: .systemOrange)))!
        XCTAssertEqual(green, 0.33, accuracy: 0.1)     // green hue ≈ 120°
        XCTAssertEqual(orange, 0.08, accuracy: 0.06)   // orange hue ≈ 30°
    }

    func testRingsAreSeparate() {
        // Along the vertical axis above the dot there must be alternating stroke / gap / stroke.
        let rep = Pixels.bitmap(StatusGlyph.image(color: .black), scale: 4)
        let x = Int(8.5 * 4)
        var runs: [Bool] = []
        for y in 0..<rep.pixelsHigh {
            let opaque = (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5
            if runs.last != opaque { runs.append(opaque) }
        }
        XCTAssertGreaterThanOrEqual(runs.filter { $0 }.count, 3, "expected ring, ring, dot as separate opaque runs; got \(runs)")
    }
}

final class SwitchRowTests: XCTestCase {
    private func click(_ view: NSView) {
        let event = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 5, y: 5), modifierFlags: [], timestamp: 0,
                                       windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        view.mouseDown(with: event)
    }

    func testToggleSwitchFlipsAndSendsAction() {
        let toggle = ToggleSwitch()
        let target = ActionTarget()
        toggle.target = target
        toggle.action = #selector(ActionTarget.fire)
        XCTAssertFalse(toggle.isOn)
        click(toggle)
        XCTAssertTrue(toggle.isOn)
        XCTAssertEqual(target.count, 1)
        click(toggle)
        XCTAssertFalse(toggle.isOn)
        XCTAssertEqual(target.count, 2)
    }

    func testDisabledToggleIgnoresClicks() {
        let toggle = ToggleSwitch()
        toggle.isEnabled = false
        click(toggle)
        XCTAssertFalse(toggle.isOn)
    }

    func testRowReportsChanges() {
        let row = SwitchMenuItemView(title: "Redirect AirDrop", isOn: false, isEnabled: true)
        var reported: [Bool] = []
        row.onChange = { reported.append($0) }
        click(row)          // anywhere on the row flips the switch
        XCTAssertEqual(reported, [true])
        click(row)
        XCTAssertEqual(reported, [true, false])
        XCTAssertTrue(row.autoresizingMask.contains(.width), "row must stretch to the menu width")
    }

    func testDisabledRowReportsNothing() {
        let row = SwitchMenuItemView(title: "x", isOn: false, isEnabled: false)
        var fired = false
        row.onChange = { _ in fired = true }
        click(row)
        XCTAssertFalse(fired)
    }

    func testDestinationRowClears() {
        let row = DestinationMenuItemView(path: "~/Movies")
        var cleared = false
        row.onClear = { cleared = true }
        let button = row.subviews.compactMap { $0 as? NSButton }.first
        XCTAssertNotNil(button)
        button?.performClick(nil)
        XCTAssertTrue(cleared)
    }
}

final class DialogTests: XCTestCase {
    func testSymbolIconIsSquareAndCentered() {
        for name in ["externaldrive.badge.xmark", "exclamationmark.triangle.fill", "arrow.turn.down.right"] {
            guard let icon = Dialog.squareSymbolIcon(name, canvas: 72, pointSize: 50, tint: .systemOrange) else { return XCTFail(name) }
            XCTAssertEqual(icon.size, NSSize(width: 72, height: 72))
            let rep = Pixels.bitmap(icon, scale: 2)
            guard let bounds = Pixels.opaqueBounds(rep) else { return XCTFail("\(name) drew nothing") }
            XCTAssertEqual(bounds.midX, CGFloat(rep.pixelsWide) / 2, accuracy: 3, "\(name) not centered horizontally")
            XCTAssertEqual(bounds.midY, CGFloat(rep.pixelsHigh) / 2, accuracy: 3, "\(name) not centered vertically")
        }
    }
}

final class SetupWindowControllerTests: XCTestCase {
    var controller: SetupWindowController!
    override func setUp() {
        Config.directory = NSTemporaryDirectory() + "airdrop2x-app-tests/" + UUID().uuidString
        controller = SetupWindowController(daemon: RedirectDaemon())
    }

    func testInstructionsState() {
        controller.apply(.instructions)
        XCTAssertEqual(controller.headingText, "Allow AirDrop to write outside Downloads")
        XCTAssertTrue(controller.bodyText.contains("/usr/libexec/sharingd"))
        XCTAssertTrue(controller.bodyText.contains("Press ⌘⇧G"))
        XCTAssertEqual(controller.buttonTitles, ["Cancel", "Open Full Disk Access", "I've added it — test now"])
    }

    func testTestingState() {
        controller.apply(.testing)
        XCTAssertEqual(controller.headingText, "Now send a test file")
        XCTAssertEqual(controller.statusText, "Waiting for an AirDrop transfer…")
        XCTAssertEqual(controller.buttonTitles, ["Cancel"])
    }

    func testFailedState() {
        controller.apply(.failed("the reason"))
        XCTAssertTrue(controller.headingText.contains("still blocked"))
        XCTAssertTrue(controller.bodyText.contains("the reason"))
        XCTAssertEqual(controller.buttonTitles, ["Cancel", "Open Full Disk Access", "Test again"])
    }

    func testSuccessState() {
        controller.apply(.success("/x/y/IMG_1.MOV"))
        XCTAssertEqual(controller.headingText, "It works")
        XCTAssertTrue(controller.bodyText.contains("IMG_1.MOV"))
        XCTAssertEqual(controller.buttonTitles, ["Done"])
    }

    func testStartTestWithoutDestinationFails() {
        controller.apply(.instructions)
        // Simulate the button without a configured destination: the window explains instead of testing.
        controller.perform(NSSelectorFromString("startTest"))
        if case .failed(let reason) = controller.state { XCTAssertTrue(reason.contains("No destination")) } else { XCTFail("expected failed state, got \(controller.state)") }
    }

    func testArrivalEventsDriveTheState() {
        controller.apply(.testing)
        controller.handle(.fallback(original: "/private/tmp/a.mov", rescuedTo: "/dest/a.mov", error: nil))
        if case .failed(let reason) = controller.state { XCTAssertTrue(reason.contains("a.mov")) } else { XCTFail() }
        controller.handle(.landed(path: "/dest/b.mov"))
        if case .success(let path) = controller.state { XCTAssertEqual(path, "/dest/b.mov") } else { XCTFail() }
        controller.close()
    }
}

final class ActionTarget: NSObject {
    var count = 0
    @objc func fire() { count += 1 }
}
