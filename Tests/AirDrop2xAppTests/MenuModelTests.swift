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
import AirDrop2xCore
@testable import AirDrop2xApp

final class MenuModelTests: XCTestCase {
    let home = "/Users/tester"
    var root = ""
    var reachable = ""

    override func setUpWithError() throws {
        root = NSTemporaryDirectory() + "airdrop2x-app-tests/" + UUID().uuidString
        reachable = root + "/dest"
        try FileManager.default.createDirectory(atPath: reachable, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(atPath: root) }

    private func config(destination: String?, enabled: Bool = false, verified: Bool = true) -> Config {
        var c = Config()
        c.destination = destination
        c.enabled = enabled
        c.grantVerified = verified
        return c
    }

    func testNoDestination() {
        let m = MenuModel.make(config: config(destination: nil), status: .inactive, login: .disabled, home: home)
        XCTAssertEqual(m.headline, "AirDrop lands in: Downloads")
        XCTAssertEqual(m.tone, .none)
        XCTAssertEqual(m.detail, "Choose a destination folder to begin")
        XCTAssertNil(m.destinationLine)
        XCTAssertFalse(m.switchEnabled)
        XCTAssertFalse(m.switchOn)
        XCTAssertEqual(m.chooseTitle, "Choose Destination…")
        XCTAssertEqual(m.setupTitle, "First-time Setup Guide…")
    }

    func testOffWithVerifiedDestination() {
        let m = MenuModel.make(config: config(destination: reachable), status: .inactive, login: .enabled, home: home)
        XCTAssertEqual(m.tone, .idle)
        XCTAssertNil(m.detail)
        XCTAssertEqual(m.destinationLine, "Destination: \(reachable)")
        XCTAssertTrue(m.switchEnabled)
        XCTAssertFalse(m.switchOn)
        XCTAssertEqual(m.chooseTitle, "Change Destination…")
        XCTAssertTrue(m.loginOn)
        XCTAssertEqual(m.loginTitle, "Start at Login")
    }

    func testOffAndUnverifiedShowsSetupHint() {
        let m = MenuModel.make(config: config(destination: reachable, verified: false), status: .inactive, login: .disabled, home: home)
        XCTAssertEqual(m.detail, "First-time setup needed before first use")
    }

    func testActive() {
        let m = MenuModel.make(config: config(destination: home + "/Movies/AirDrop", enabled: true),
                               status: .active(destination: home + "/Movies/AirDrop"), login: .disabled, home: home)
        XCTAssertEqual(m.headline, "AirDrop lands in: ~/Movies/AirDrop")
        XCTAssertEqual(m.tone, .active)
        XCTAssertNil(m.detail)
        XCTAssertTrue(m.switchOn)
        XCTAssertEqual(m.destinationLine, "Destination: ~/Movies/AirDrop")
    }

    func testOnButDestinationUnreachableIsWaiting() {
        let gone = root + "/gone"
        let m = MenuModel.make(config: config(destination: gone, enabled: true), status: .inactive, login: .disabled, home: home)
        XCTAssertEqual(m.tone, .idle)
        XCTAssertEqual(m.detail, "Waiting for \(gone) to come back")
        XCTAssertTrue(m.switchOn)
    }

    func testDangling() {
        let m = MenuModel.make(config: config(destination: reachable, enabled: true), status: .dangling(destination: reachable), login: .disabled, home: home)
        XCTAssertEqual(m.headline, "AirDrop: destination not reachable")
        XCTAssertEqual(m.detail, "Waiting for \(reachable) to come back")
        XCTAssertEqual(m.tone, .idle)
    }

    func testConflictAndOtherStates() {
        let conflict = MenuModel.make(config: config(destination: reachable), status: .conflict("both exist"), login: .disabled, home: home)
        XCTAssertEqual(conflict.headline, "Attention needed")
        XCTAssertEqual(conflict.detail, "both exist")
        XCTAssertEqual(MenuModel.make(config: config(destination: reachable), status: .missing, login: .disabled, home: home).headline, "No Downloads folder found")
        XCTAssertEqual(MenuModel.make(config: config(destination: reachable), status: .otherLink(target: "/x"), login: .disabled, home: home).headline,
                       "Downloads is a symlink made by something else")
    }

    func testLoginRequiresApproval() {
        let m = MenuModel.make(config: config(destination: nil), status: .inactive, login: .requiresApproval, home: home)
        XCTAssertEqual(m.loginTitle, "Start at Login (approve in System Settings)")
        XCTAssertFalse(m.loginOn)
    }

    func testShortPath() {
        XCTAssertEqual(MenuModel.shortPath(home + "/Downloads", home: home), "~/Downloads")
        XCTAssertEqual(MenuModel.shortPath(home, home: home), home, "the home folder itself is left as is")
        XCTAssertEqual(MenuModel.shortPath("/Volumes/SSD/x", home: home), "/Volumes/SSD/x")
        XCTAssertEqual(MenuModel.shortPath(home + "x/y", home: home), home + "x/y", "prefix must be a path component")
    }

    func testColorsPerTone() {
        XCTAssertEqual(AppDelegate.color(for: .active), .systemGreen)
        XCTAssertEqual(AppDelegate.color(for: .idle), .systemOrange)
        XCTAssertEqual(AppDelegate.color(for: .none), .systemGray)
    }
}
