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

final class ConfigTests: XCTestCase {
    var sandbox: Sandbox!
    override func setUpWithError() throws { sandbox = try Sandbox() }
    override func tearDown() { sandbox.tearDown() }

    func testDefaults() {
        let config = Config()
        XCTAssertNil(config.destination)
        XCTAssertFalse(config.enabled)
        XCTAssertTrue(config.downloadsFolder.hasSuffix("/Downloads"))
        XCTAssertTrue(config.parkedFolder.hasSuffix("/Downloads.local"))
        XCTAssertEqual(config.pollSeconds, 2)
        XCTAssertEqual(config.reminderMinutes, 5)
        XCTAssertTrue(config.notify)
        XCTAssertFalse(config.grantVerified)
    }

    func testLoadReturnsDefaultsWhenNoFile() {
        XCTAssertFalse(FileManager.default.fileExists(atPath: Config.path))
        XCTAssertNil(Config.load().destination)
    }

    func testSaveAndLoadRoundTrip() throws {
        var config = sandbox.config
        config.enabled = true
        config.reminderMinutes = 7.5
        config.grantVerified = false
        try config.save()
        let loaded = Config.load()
        XCTAssertEqual(loaded.destination, sandbox.destination)
        XCTAssertEqual(loaded.downloadsFolder, sandbox.downloads)
        XCTAssertEqual(loaded.parkedFolder, sandbox.parked)
        XCTAssertTrue(loaded.enabled)
        XCTAssertEqual(loaded.reminderMinutes, 7.5)
        XCTAssertEqual(loaded.pollSeconds, 0.2)
        XCTAssertFalse(loaded.grantVerified)
    }

    func testLoadToleratesMissingKeys() throws {
        try #"{"destination": "/tmp/x", "enabled": true}"#.write(toFile: Config.path, atomically: true, encoding: .utf8)
        let loaded = Config.load()
        XCTAssertEqual(loaded.destination, "/tmp/x")
        XCTAssertTrue(loaded.enabled)
        XCTAssertEqual(loaded.pollSeconds, 2, "missing keys fall back to defaults")
        XCTAssertEqual(loaded.reminderMinutes, 5)
    }

    func testLoadFallsBackToDefaultsOnGarbage() throws {
        try "this is not json".write(toFile: Config.path, atomically: true, encoding: .utf8)
        XCTAssertNil(Config.load().destination)
        XCTAssertFalse(Config.load().enabled)
    }

    func testSaveCreatesDirectory() throws {
        Config.directory = sandbox.root + "/cfg/nested/deeper"
        try sandbox.config.save()
        XCTAssertTrue(FileManager.default.fileExists(atPath: Config.path))
    }

    func testDescribeListsKeySettings() {
        let text = sandbox.config.describe()
        XCTAssertTrue(text.contains(sandbox.destination))
        XCTAssertTrue(text.contains("switch:            off"))
        XCTAssertTrue(text.contains("reminder minutes"))
    }

    func testNormalizePath() {
        XCTAssertEqual(normalizePath("~/Foo"), NSHomeDirectory() + "/Foo")
        XCTAssertEqual(normalizePath("/a/b/../c/"), "/a/c")
        let cwd = FileManager.default.currentDirectoryPath
        XCTAssertEqual(normalizePath("rel/x"), cwd + "/rel/x")
    }

    func testFileLockIsExclusiveUntilReleased() {
        var first: FileLock? = FileLock(path: Config.lockPath)
        XCTAssertNotNil(first)
        var acquired = false
        DispatchQueue.global().async {
            let second = FileLock(path: Config.lockPath)
            XCTAssertNotNil(second)
            acquired = true
            withExtendedLifetime(second) {}
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        XCTAssertFalse(acquired, "second lock must wait while the first is held")
        first = nil
        XCTAssertTrue(waitUntil { acquired })
        withExtendedLifetime(first) {}
    }
}
