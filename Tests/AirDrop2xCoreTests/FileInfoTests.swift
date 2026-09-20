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

final class FileInfoTests: XCTestCase {
    var sandbox: Sandbox!
    override func setUpWithError() throws { sandbox = try Sandbox() }
    override func tearDown() { sandbox.tearDown() }

    func testRegularFile() {
        let path = Sandbox.writeFile(sandbox.root + "/f.bin", bytes: 4096)
        let info = FileInfo(path: path)
        XCTAssertNotNil(info)
        XCTAssertTrue(info!.isRegular)
        XCTAssertFalse(info!.isDirectory)
        XCTAssertFalse(info!.isSymlink)
        XCTAssertEqual(info!.size, 4096)
        XCTAssertLessThan(abs(info!.created.timeIntervalSinceNow), 5)
    }

    func testDirectoryAndSymlink() throws {
        XCTAssertTrue(FileInfo(path: sandbox.destination)!.isDirectory)
        let link = sandbox.root + "/link"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: sandbox.destination)
        let viaLstat = FileInfo(path: link)!
        XCTAssertTrue(viaLstat.isSymlink)
        XCTAssertFalse(viaLstat.isDirectory)
        let viaStat = FileInfo(path: link, followSymlinks: true)!
        XCTAssertTrue(viaStat.isDirectory)
        XCTAssertFalse(viaStat.isSymlink)
    }

    func testMissingPathIsNil() {
        XCTAssertNil(FileInfo(path: sandbox.root + "/missing"))
    }

    func testQuarantineAgentParsing() {
        let path = Sandbox.writeFile(sandbox.root + "/q")
        XCTAssertNil(Quarantine.agent(of: path))
        XCTAssertFalse(Quarantine.isAirDrop(path))
        Sandbox.markQuarantine(path, agent: "Safari")
        XCTAssertEqual(Quarantine.agent(of: path), "Safari")
        XCTAssertFalse(Quarantine.isAirDrop(path))
        Sandbox.markAirDrop(path)
        XCTAssertEqual(Quarantine.agent(of: path), "sharingd")
        XCTAssertTrue(Quarantine.isAirDrop(path))
    }

    func testMalformedQuarantineIsIgnored() {
        let path = Sandbox.writeFile(sandbox.root + "/bad")
        _ = "garbage".withCString { setxattr(path, "com.apple.quarantine", $0, strlen($0), 0, 0) }
        XCTAssertNil(Quarantine.agent(of: path))
    }
}
