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
@testable import AirDrop2xCore

final class RedirectTests: XCTestCase {
    var sandbox: Sandbox!
    override func setUpWithError() throws { sandbox = try Sandbox() }
    override func tearDown() { sandbox.tearDown() }

    // MARK: status

    func testStatusInactiveForRealFolder() {
        XCTAssertEqual(Redirect.status(sandbox.config), .inactive)
        XCTAssertFalse(Redirect.status(sandbox.config).isActive)
    }

    func testStatusMissingWhenNothingExists() throws {
        try FileManager.default.removeItem(atPath: sandbox.downloads)
        XCTAssertEqual(Redirect.status(sandbox.config), .missing)
    }

    func testStatusConflictWhenBothRealAndParkedExist() throws {
        try FileManager.default.createDirectory(atPath: sandbox.parked, withIntermediateDirectories: false)
        if case .conflict = Redirect.status(sandbox.config) {} else { XCTFail("expected conflict") }
    }

    func testStatusConflictWhenOnlyParkedExists() throws {
        XCTAssertEqual(rename(sandbox.downloads, sandbox.parked), 0)
        if case .conflict = Redirect.status(sandbox.config) {} else { XCTFail("expected conflict") }
    }

    func testStatusOtherLink() throws {
        try FileManager.default.removeItem(atPath: sandbox.downloads)
        try FileManager.default.createSymbolicLink(atPath: sandbox.downloads, withDestinationPath: sandbox.root)
        XCTAssertEqual(Redirect.status(sandbox.config), .otherLink(target: sandbox.root))
    }

    // MARK: apply

    func testApplyParksDownloadsAndLinksToDestination() throws {
        XCTAssertTrue(try Redirect.apply(sandbox.config))
        XCTAssertTrue(sandbox.isSymlink(sandbox.downloads))
        XCTAssertEqual(sandbox.linkTarget(sandbox.downloads), sandbox.destination)
        XCTAssertTrue(sandbox.isDirectory(sandbox.parked))
        XCTAssertTrue(sandbox.exists(sandbox.parked + "/existing.txt"), "contents travel with the parked folder")
        XCTAssertEqual(Redirect.status(sandbox.config), .active(destination: sandbox.destination))
        // A file written through the link lands in the destination.
        Sandbox.writeFile(sandbox.downloads + "/via-link.txt")
        XCTAssertTrue(sandbox.exists(sandbox.destination + "/via-link.txt"))
    }

    func testApplyIsIdempotent() throws {
        XCTAssertTrue(try Redirect.apply(sandbox.config))
        XCTAssertFalse(try Redirect.apply(sandbox.config))
        XCTAssertTrue(Redirect.status(sandbox.config).isActive)
    }

    func testApplyRequiresDestination() {
        var config = sandbox.config
        config.destination = nil
        XCTAssertThrowsError(try Redirect.apply(config))
        XCTAssertTrue(sandbox.isDirectory(sandbox.downloads), "nothing touched")
    }

    func testApplyRefusesUnreachableDestination() throws {
        try FileManager.default.removeItem(atPath: sandbox.destination)
        XCTAssertThrowsError(try Redirect.apply(sandbox.config))
        XCTAssertTrue(sandbox.isDirectory(sandbox.downloads))
        XCTAssertFalse(sandbox.exists(sandbox.parked))
    }

    func testApplyRefusesConflict() throws {
        try FileManager.default.createDirectory(atPath: sandbox.parked, withIntermediateDirectories: false)
        XCTAssertThrowsError(try Redirect.apply(sandbox.config))
        XCTAssertTrue(sandbox.isDirectory(sandbox.downloads))
    }

    func testApplyReplacesForeignSymlink() throws {
        try FileManager.default.removeItem(atPath: sandbox.downloads)
        try FileManager.default.createSymbolicLink(atPath: sandbox.downloads, withDestinationPath: sandbox.root)
        XCTAssertTrue(try Redirect.apply(sandbox.config))
        XCTAssertEqual(sandbox.linkTarget(sandbox.downloads), sandbox.destination)
        XCTAssertFalse(sandbox.exists(sandbox.parked), "there was no real folder to park")
    }

    func testApplyWhenDownloadsMissingButParkedExists() throws {
        XCTAssertEqual(rename(sandbox.downloads, sandbox.parked), 0)   // crash between the two steps
        XCTAssertTrue(try Redirect.apply(sandbox.config))
        XCTAssertEqual(sandbox.linkTarget(sandbox.downloads), sandbox.destination)
    }

    func testApplyLiftsProtectiveACLAndRestorePutsItBack() throws {
        Sandbox.addDenyDeleteACL(sandbox.downloads)
        XCTAssertTrue(try Redirect.apply(sandbox.config))
        XCTAssertTrue(sandbox.isSymlink(sandbox.downloads))
        XCTAssertTrue(try Redirect.restore(sandbox.config))
        XCTAssertTrue(sandbox.isDirectory(sandbox.downloads))
        XCTAssertTrue(Sandbox.hasDenyDeleteACL(sandbox.downloads), "protective entry restored")
    }

    // MARK: restore

    func testRestoreUnlinksAndUnparks() throws {
        try Redirect.apply(sandbox.config)
        XCTAssertTrue(try Redirect.restore(sandbox.config))
        XCTAssertTrue(sandbox.isDirectory(sandbox.downloads))
        XCTAssertTrue(sandbox.exists(sandbox.downloads + "/existing.txt"))
        XCTAssertFalse(sandbox.exists(sandbox.parked))
        XCTAssertEqual(Redirect.status(sandbox.config), .inactive)
    }

    func testRestoreIsIdempotent() throws {
        XCTAssertFalse(try Redirect.restore(sandbox.config))
        XCTAssertTrue(sandbox.isDirectory(sandbox.downloads))
    }

    func testRestoreHandlesDanglingLink() throws {
        try Redirect.apply(sandbox.config)
        try FileManager.default.removeItem(atPath: sandbox.destination)
        XCTAssertEqual(Redirect.status(sandbox.config), .dangling(destination: sandbox.destination))
        XCTAssertTrue(try Redirect.restore(sandbox.config))
        XCTAssertTrue(sandbox.isDirectory(sandbox.downloads))
        XCTAssertTrue(sandbox.exists(sandbox.downloads + "/existing.txt"))
    }

    func testRestoreCreatesEmptyDownloadsWhenParkedIsGone() throws {
        try Redirect.apply(sandbox.config)
        try FileManager.default.removeItem(atPath: sandbox.parked)
        XCTAssertTrue(try Redirect.restore(sandbox.config))
        XCTAssertTrue(sandbox.isDirectory(sandbox.downloads))
    }

    func testRestoreFixesParkedOnlyConflict() throws {
        XCTAssertEqual(rename(sandbox.downloads, sandbox.parked), 0)
        XCTAssertTrue(try Redirect.restore(sandbox.config))
        XCTAssertTrue(sandbox.isDirectory(sandbox.downloads))
        XCTAssertFalse(sandbox.exists(sandbox.parked))
    }

    func testRestoreRefusesRealAndParkedConflict() throws {
        try FileManager.default.createDirectory(atPath: sandbox.parked, withIntermediateDirectories: false)
        XCTAssertThrowsError(try Redirect.restore(sandbox.config))
        XCTAssertTrue(sandbox.isDirectory(sandbox.downloads))
        XCTAssertTrue(sandbox.isDirectory(sandbox.parked))
    }

    func testRestoreCreatesDownloadsWhenEverythingIsMissing() throws {
        try FileManager.default.removeItem(atPath: sandbox.downloads)
        XCTAssertTrue(try Redirect.restore(sandbox.config))
        XCTAssertTrue(sandbox.isDirectory(sandbox.downloads))
    }

    func testFullCycleKeepsUserData() throws {
        for _ in 0..<3 {
            try Redirect.apply(sandbox.config)
            try Redirect.restore(sandbox.config)
        }
        XCTAssertEqual(try String(contentsOfFile: sandbox.downloads + "/existing.txt"), "existing")
    }

    // MARK: describe & helpers

    func testDescribe() {
        XCTAssertTrue(Redirect.describe(.inactive).hasPrefix("OFF"))
        XCTAssertTrue(Redirect.describe(.active(destination: "/x")).contains("/x"))
        XCTAssertTrue(Redirect.describe(.dangling(destination: "/x")).contains("DANGLING"))
        XCTAssertTrue(Redirect.describe(.conflict("why")).contains("why"))
        XCTAssertTrue(Redirect.describe(.missing).contains("no Downloads"))
        XCTAssertTrue(Redirect.describe(.otherLink(target: "/t")).contains("/t"))
    }

    func testResetSharingHelperUsesInjectedResetter() {
        Redirect.resetSharingHelper()
        XCTAssertEqual(sandbox.helperResets, 1)
    }
}
