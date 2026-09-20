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

import Foundation
import AirDrop2xCore

/// What the menu shows for a given configuration and redirect state. Pure data, so it can be
/// tested without a status item or a window server.
struct MenuModel: Equatable {
    enum Tone { case active, idle, none }   // green, orange, grey
    enum LoginState { case enabled, requiresApproval, disabled }

    var headline: String
    var tone: Tone
    var detail: String?
    var destinationLine: String?
    var switchOn: Bool
    var switchEnabled: Bool
    var chooseTitle: String
    var setupTitle: String
    var loginTitle: String
    var loginOn: Bool

    static func make(config: Config, status: Redirect.Status, login: LoginState, home: String = NSHomeDirectory()) -> MenuModel {
        let destination = config.destination
        let short = destination.map { shortPath($0, home: home) }

        let headline: String
        switch status {
        case .active(let d): headline = "AirDrop lands in: \(shortPath(d, home: home))"
        case .inactive:      headline = "AirDrop lands in: Downloads"
        case .dangling:      headline = "AirDrop: destination not reachable"
        case .otherLink:     headline = "Downloads is a symlink made by something else"
        case .missing:       headline = "No Downloads folder found"
        case .conflict:      headline = "Attention needed"
        }

        let detail: String?
        switch status {
        case .conflict(let why): detail = why
        case .dangling(let d):   detail = "Waiting for \(shortPath(d, home: home)) to come back"
        default:
            if let destination = destination, let short = short {
                if status.isActive { detail = nil }   // active already means reachable; no extra check
                else if config.enabled, !Destination.isReachable(destination) { detail = "Waiting for \(short) to come back" }
                else if !config.enabled, !config.grantVerified { detail = "First-time setup needed before first use" }
                else { detail = nil }
            } else {
                detail = "Choose a destination folder to begin"
            }
        }

        let tone: Tone = destination == nil ? .none : (status.isActive ? .active : .idle)
        let loginTitle = login == .requiresApproval ? "Start at Login (approve in System Settings)" : "Start at Login"

        return MenuModel(headline: headline,
                         tone: tone,
                         detail: detail,
                         destinationLine: short.map { "Destination: \($0)" },
                         switchOn: config.enabled,
                         switchEnabled: destination != nil,
                         chooseTitle: destination == nil ? "Choose Destination…" : "Change Destination…",
                         setupTitle: "First-time Setup Guide…",
                         loginTitle: loginTitle,
                         loginOn: login == .enabled)
    }

    static func shortPath(_ path: String, home: String = NSHomeDirectory()) -> String {
        path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}
