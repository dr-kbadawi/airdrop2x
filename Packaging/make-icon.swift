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

// Generates AppIcon.icns: a derivative of the AirDrop motif (concentric arcs over a dot on a blue tile)
// with a small arrow leaving the dot, for "redirected".
import AppKit

let out = CommandLine.arguments.dropFirst().first ?? "AppIcon.icns"
let iconset = "AppIcon.iconset"
try? FileManager.default.removeItem(atPath: iconset)
try! FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

func render(_ size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let s = size / 1024   // design in a 1024 grid

    // Tile: light, like Apple's AirDrop icon.
    let inset = 60 * s
    let tile = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 230 * s, yRadius: 230 * s)
    NSGradient(starting: NSColor(calibratedWhite: 1.0, alpha: 1), ending: NSColor(calibratedWhite: 0.90, alpha: 1))!.draw(in: tilePath, angle: -90)
    NSColor(calibratedWhite: 0.78, alpha: 1).setStroke()
    tilePath.lineWidth = 4 * s
    tilePath.stroke()

    let blue = NSColor(calibratedRed: 0.08, green: 0.47, blue: 0.96, alpha: 1)
    blue.setStroke()
    blue.setFill()

    // Rings around a dot, interrupted by a wedge opening downward (the AirDrop motif).
    let center = NSPoint(x: 512 * s, y: 620 * s)
    let halfWedge: CGFloat = 32   // degrees either side of straight down
    for radius in [125.0, 215.0, 305.0] {
        let ring = NSBezierPath()
        ring.appendArc(withCenter: center, radius: CGFloat(radius) * s, startAngle: 270 + halfWedge, endAngle: 270 - halfWedge, clockwise: false)
        ring.lineWidth = 50 * s
        ring.lineCapStyle = .round
        ring.stroke()
    }
    NSBezierPath(ovalIn: NSRect(x: center.x - 44 * s, y: center.y - 44 * s, width: 88 * s, height: 88 * s)).fill()

    // Redirect arrow inside the wedge: down from the dot, bend, then right.
    let stroke = 50 * s
    let bendRadius = 90 * s
    let yBottom = 185 * s
    let xTip = 800 * s
    let path = NSBezierPath()
    path.move(to: NSPoint(x: center.x, y: center.y - 75 * s))
    path.line(to: NSPoint(x: center.x, y: yBottom + bendRadius))
    path.appendArc(withCenter: NSPoint(x: center.x + bendRadius, y: yBottom + bendRadius), radius: bendRadius, startAngle: 180, endAngle: 270, clockwise: false)
    path.line(to: NSPoint(x: xTip - 110 * s, y: yBottom))
    path.lineWidth = stroke
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: xTip, y: yBottom))
    head.line(to: NSPoint(x: xTip - 135 * s, y: yBottom + 85 * s))
    head.line(to: NSPoint(x: xTip - 135 * s, y: yBottom - 85 * s))
    head.close()
    head.lineJoinStyle = .round
    head.lineWidth = 22 * s
    head.fill()
    head.stroke()

    image.unlockFocus()
    return image
}

for (points, scale) in [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)] {
    let px = CGFloat(points * scale)
    let image = render(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(px), pixelsHigh: Int(px), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(iconset)/\(name)"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset, "-o", out]
try! task.run(); task.waitUntilExit()
try? FileManager.default.removeItem(atPath: iconset)
print(task.terminationStatus == 0 ? "wrote \(out)" : "iconutil failed")
