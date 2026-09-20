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

/// The app's glyph for the menu bar: rings with a downward wedge around a dot, plus the bent redirect
/// arrow, in a state color. Proportions are tuned for ~20 points, not scaled from the app icon: at this
/// size three closely spaced rings would fuse into a disc, so it uses two rings with clear gaps.
enum StatusGlyph {
    static func image(color: NSColor) -> NSImage {
        let size = NSSize(width: 18, height: 20)
        let image = NSImage(size: size, flipped: false) { _ in
            color.setStroke()
            color.setFill()
            let center = NSPoint(x: 8.5, y: 12.5)
            let halfWedge: CGFloat = 34
            let line: CGFloat = 1.4

            for radius in [3.6, 6.4] as [CGFloat] {
                let ring = NSBezierPath()
                ring.appendArc(withCenter: center, radius: radius, startAngle: 270 + halfWedge, endAngle: 270 - halfWedge, clockwise: false)
                ring.lineWidth = line
                ring.lineCapStyle = .round
                ring.stroke()
            }
            NSBezierPath(ovalIn: NSRect(x: center.x - 1.5, y: center.y - 1.5, width: 3, height: 3)).fill()

            // Arrow: down from the dot through the wedge, bend, then right under the rings.
            let bend: CGFloat = 2.2
            let yBottom: CGFloat = 4.0
            let tipX: CGFloat = 17.2
            let path = NSBezierPath()
            path.move(to: NSPoint(x: center.x, y: center.y - 2.4))
            path.line(to: NSPoint(x: center.x, y: yBottom + bend))
            path.appendArc(withCenter: NSPoint(x: center.x + bend, y: yBottom + bend), radius: bend, startAngle: 180, endAngle: 270, clockwise: false)
            path.line(to: NSPoint(x: tipX - 2.6, y: yBottom))
            path.lineWidth = line
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()
            let head = NSBezierPath()
            head.move(to: NSPoint(x: tipX, y: yBottom))
            head.line(to: NSPoint(x: tipX - 3.2, y: yBottom + 2.3))
            head.line(to: NSPoint(x: tipX - 3.2, y: yBottom - 2.3))
            head.close()
            head.lineJoinStyle = .round
            head.lineWidth = 0.8
            head.fill()
            head.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }
}
