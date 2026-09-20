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

final class ArrivalsTests: XCTestCase {
    var sandbox: Sandbox!
    let queue = DispatchQueue(label: "arrivals-tests")
    override func setUpWithError() throws { sandbox = try Sandbox() }
    override func tearDown() { sandbox.tearDown() }

    private func watch(_ folders: [String], since: Date = Date(), handler: @escaping (ArrivalWatcher.Arrival) -> Void) -> ArrivalWatcher {
        let watcher = ArrivalWatcher(folders: folders, since: since, queue: queue, handler: handler)
        watcher.start()
        return watcher
    }

    func testReportsAirDropFileOnceStable() {
        var arrivals: [ArrivalWatcher.Arrival] = []
        let watcher = watch([sandbox.destination]) { arrivals.append($0) }
        defer { watcher.stop() }
        let path = Sandbox.writeFile(sandbox.destination + "/IMG_1.MOV", bytes: 2000)
        Sandbox.markAirDrop(path)
        XCTAssertTrue(waitUntil(timeout: 8) { !arrivals.isEmpty })
        XCTAssertEqual(arrivals.first?.path, path)
        XCTAssertEqual(arrivals.first?.folder, sandbox.destination)
        RunLoop.main.run(until: Date().addingTimeInterval(2.5))
        XCTAssertEqual(arrivals.count, 1, "reported exactly once")
    }

    func testIgnoresFilesWithoutAirDropTag() {
        var arrivals = 0
        let watcher = watch([sandbox.destination]) { _ in arrivals += 1 }
        defer { watcher.stop() }
        Sandbox.writeFile(sandbox.destination + "/plain.txt")
        let safari = Sandbox.writeFile(sandbox.destination + "/dl.pdf")
        Sandbox.markQuarantine(safari, agent: "Safari")
        RunLoop.main.run(until: Date().addingTimeInterval(3.5))
        XCTAssertEqual(arrivals, 0)
    }

    func testIgnoresItemsOlderThanSince() {
        let old = Sandbox.writeFile(sandbox.destination + "/old.jpg")
        Sandbox.markAirDrop(old)
        RunLoop.main.run(until: Date().addingTimeInterval(1.6))   // clear the one-second tolerance
        var arrivals = 0
        let watcher = watch([sandbox.destination], since: Date()) { _ in arrivals += 1 }
        defer { watcher.stop() }
        RunLoop.main.run(until: Date().addingTimeInterval(3.5))
        XCTAssertEqual(arrivals, 0)
    }

    func testIgnoredPathIsNeverReported() {
        var arrivals = 0
        let watcher = watch([sandbox.destination]) { _ in arrivals += 1 }
        defer { watcher.stop() }
        let path = Sandbox.writeFile(sandbox.destination + "/moved-by-us.mov")
        Sandbox.markAirDrop(path)
        queue.sync { watcher.ignore(path) }
        RunLoop.main.run(until: Date().addingTimeInterval(3.5))
        XCTAssertEqual(arrivals, 0)
    }

    func testGrowingFileIsReportedOnlyAfterItStopsGrowing() {
        var reportedAt: Date?
        let watcher = watch([sandbox.destination]) { _ in reportedAt = Date() }
        defer { watcher.stop() }
        let path = Sandbox.writeFile(sandbox.destination + "/big.mov", bytes: 100)
        Sandbox.markAirDrop(path)
        let start = Date()
        // Keep appending for 3 seconds: the file must not be reported while it changes.
        let handle = FileHandle(forWritingAtPath: path)!
        while Date().timeIntervalSince(start) < 3 {
            handle.seekToEndOfFile()
            handle.write(Data(repeating: 0x42, count: 512))
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        }
        handle.closeFile()
        XCTAssertNil(reportedAt, "not reported while still growing")
        XCTAssertTrue(waitUntil(timeout: 8) { reportedAt != nil })
        XCTAssertGreaterThan(reportedAt!.timeIntervalSince(start), 3)
    }

    func testWatchesSeveralFoldersAndReportsWhichOne() {
        var folders: [String] = []
        let watcher = watch([sandbox.fallback, sandbox.destination]) { folders.append($0.folder) }
        defer { watcher.stop() }
        Sandbox.markAirDrop(Sandbox.writeFile(sandbox.fallback + "/tmp.png"))
        XCTAssertTrue(waitUntil(timeout: 8) { !folders.isEmpty })
        XCTAssertEqual(folders, [sandbox.fallback])
    }

    func testStopEndsReporting() {
        var arrivals = 0
        let watcher = watch([sandbox.destination]) { _ in arrivals += 1 }
        watcher.stop()
        Sandbox.markAirDrop(Sandbox.writeFile(sandbox.destination + "/late.png"))
        RunLoop.main.run(until: Date().addingTimeInterval(3.5))
        XCTAssertEqual(arrivals, 0)
    }

    // MARK: Rescue

    func testUniqueDestinationNaming() throws {
        let dir = sandbox.destination
        XCTAssertEqual(Rescue.uniqueDestination(directory: dir, name: "a.txt"), dir + "/a.txt")
        Sandbox.writeFile(dir + "/a.txt")
        XCTAssertEqual(Rescue.uniqueDestination(directory: dir, name: "a.txt"), dir + "/a 2.txt")
        Sandbox.writeFile(dir + "/a 2.txt")
        XCTAssertEqual(Rescue.uniqueDestination(directory: dir, name: "a.txt"), dir + "/a 3.txt")
        Sandbox.writeFile(dir + "/noext")
        XCTAssertEqual(Rescue.uniqueDestination(directory: dir, name: "noext"), dir + "/noext 2")
    }

    func testRescueMovesFileAndKeepsName() throws {
        let source = Sandbox.writeFile(sandbox.fallback + "/clip.mov", bytes: 3000)
        let target = try Rescue.move(source, toDirectory: sandbox.destination)
        XCTAssertEqual(target, sandbox.destination + "/clip.mov")
        XCTAssertFalse(sandbox.exists(source))
        XCTAssertEqual(FileInfo(path: target)?.size, 3000)
    }

    func testRescueRefusesUnreachableDestination() throws {
        let source = Sandbox.writeFile(sandbox.fallback + "/x.mov")
        XCTAssertThrowsError(try Rescue.move(source, toDirectory: sandbox.root + "/gone"))
        XCTAssertTrue(sandbox.exists(source), "source untouched on failure")
    }
}
