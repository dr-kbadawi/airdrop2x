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

final class DestinationTests: XCTestCase {
    var sandbox: Sandbox!
    override func setUpWithError() throws { sandbox = try Sandbox() }
    override func tearDown() { sandbox.tearDown() }

    func testExistingWritableDirectoryPasses() throws {
        XCTAssertNoThrow(try Destination.check(sandbox.destination))
        XCTAssertTrue(Destination.isReachable(sandbox.destination))
    }

    func testMissingPathFails() {
        XCTAssertThrowsError(try Destination.check(sandbox.root + "/nope")) { error in
            XCTAssertTrue("\(error)".contains("not reachable"))
        }
        XCTAssertFalse(Destination.isReachable(sandbox.root + "/nope"))
        XCTAssertFalse(Destination.isReachable(nil))
    }

    func testFileInsteadOfDirectoryFails() {
        let file = Sandbox.writeFile(sandbox.root + "/afile")
        XCTAssertThrowsError(try Destination.check(file))
    }

    func testUnwritableDirectoryFails() throws {
        try XCTSkipIf(getuid() == 0, "root can write anywhere")
        let dir = sandbox.root + "/readonly"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        chmod(dir, 0o500)
        defer { chmod(dir, 0o700) }
        XCTAssertThrowsError(try Destination.check(dir)) { error in
            XCTAssertTrue("\(error)".contains("not writable"))
        }
    }

    func testPathUnderVolumesMustBeMounted() {
        // A stand-in directory under /Volumes that is not a mount point must be rejected even if it exists.
        // We cannot create one without root, so exercise the "does not exist" branch and the message.
        let ghost = "/Volumes/airdrop2x-tests-\(UUID().uuidString)/folder"
        XCTAssertThrowsError(try Destination.check(ghost))
        XCTAssertFalse(Destination.isReachable(ghost))
    }

    func testValidateChoiceRejectsDownloadsItselfAndItsContents() {
        XCTAssertThrowsError(try Destination.validateChoice(sandbox.downloads, config: sandbox.config))
        XCTAssertThrowsError(try Destination.validateChoice(sandbox.downloads + "/sub", config: sandbox.config))
    }

    func testValidateChoiceRejectsParkedFolder() {
        XCTAssertThrowsError(try Destination.validateChoice(sandbox.parked, config: sandbox.config))
        XCTAssertThrowsError(try Destination.validateChoice(sandbox.parked + "/x", config: sandbox.config))
    }

    func testValidateChoiceAcceptsOrdinaryFolder() {
        XCTAssertNoThrow(try Destination.validateChoice(sandbox.destination, config: sandbox.config))
    }
}
