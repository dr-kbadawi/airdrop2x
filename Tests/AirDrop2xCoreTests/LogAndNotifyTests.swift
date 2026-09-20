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

final class LogAndNotifyTests: XCTestCase {
    var sandbox: Sandbox!
    override func setUpWithError() throws { sandbox = try Sandbox() }
    override func tearDown() { Log.filePath = nil; Log.verbose = false; sandbox.tearDown() }

    func testLogWritesToFileWhenConfigured() throws {
        let path = sandbox.root + "/test.log"
        Log.filePath = path
        Log.info("hello world")
        Log.warn("careful")
        Log.error("boom")
        let text = try String(contentsOfFile: path)
        XCTAssertTrue(text.contains("[INFO ] hello world"))
        XCTAssertTrue(text.contains("[WARN ] careful"))
        XCTAssertTrue(text.contains("[ERROR] boom"))
        XCTAssertEqual(text.components(separatedBy: "\n").filter { !$0.isEmpty }.count, 3)
    }

    func testDebugOnlyWhenVerbose() throws {
        let path = sandbox.root + "/v.log"
        Log.filePath = path
        Log.debug("hidden")
        Log.verbose = true
        Log.debug("shown")
        let text = try String(contentsOfFile: path)
        XCTAssertFalse(text.contains("hidden"))
        XCTAssertTrue(text.contains("[DEBUG] shown"))
    }

    func testFormatBytes() {
        XCTAssertEqual(formatBytes(512), "512 B")
        XCTAssertEqual(formatBytes(2048), "2.0 KB")
        XCTAssertEqual(formatBytes(5 * 1024 * 1024), "5.0 MB")
    }

    func testNotifierSinkReceivesNotifications() {
        showNotification(title: "T", body: "B")
        XCTAssertEqual(sandbox.notifications.count, 1)
        XCTAssertEqual(sandbox.notifications[0].title, "T")
        XCTAssertEqual(sandbox.notifications[0].body, "B")
    }
}
