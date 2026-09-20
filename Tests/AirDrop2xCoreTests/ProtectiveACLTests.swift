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

final class ProtectiveACLTests: XCTestCase {
    var sandbox: Sandbox!
    override func setUpWithError() throws { sandbox = try Sandbox() }
    override func tearDown() { sandbox.tearDown() }

    func testAddRemoveDetect() throws {
        let dir = sandbox.downloads
        XCTAssertFalse(ProtectiveACL.isPresent(on: dir))
        ProtectiveACL.add(to: dir)
        XCTAssertTrue(ProtectiveACL.isPresent(on: dir))
        XCTAssertTrue(Sandbox.hasDenyDeleteACL(dir))
        // With the entry present, a rename is refused, which is the whole reason the entry matters.
        XCTAssertNotEqual(rename(dir, sandbox.parked), 0)
        try ProtectiveACL.remove(from: dir)
        XCTAssertFalse(ProtectiveACL.isPresent(on: dir))
        XCTAssertEqual(rename(dir, sandbox.parked), 0)
        XCTAssertEqual(rename(sandbox.parked, dir), 0)
    }

    func testRemoveWithoutEntryIsNoop() {
        XCTAssertNoThrow(try ProtectiveACL.remove(from: sandbox.destination))
    }

    func testAddTwiceKeepsOneEntry() {
        ProtectiveACL.add(to: sandbox.destination)
        ProtectiveACL.add(to: sandbox.destination)
        let listing = Sandbox.run("/bin/ls", ["-lde", sandbox.destination])
        XCTAssertEqual(listing.components(separatedBy: "everyone deny delete").count - 1, 1)
        try? ProtectiveACL.remove(from: sandbox.destination)
    }
}
