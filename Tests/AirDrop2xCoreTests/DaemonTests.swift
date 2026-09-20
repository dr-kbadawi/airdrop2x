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

final class DaemonTests: XCTestCase {
    var sandbox: Sandbox!
    var daemon: RedirectDaemon!
    var statuses: [Redirect.Status] = []
    var events: [RedirectDaemon.ArrivalEvent] = []

    override func setUpWithError() throws {
        sandbox = try Sandbox()
        daemon = RedirectDaemon()
        daemon.onStatusChange = { [weak self] in self?.statuses.append($0) }
        daemon.onArrival = { [weak self] in self?.events.append($0) }
    }

    override func tearDown() {
        daemon.stop()
        daemon = nil
        sandbox.tearDown()
    }

    private var current: Redirect.Status { Redirect.status(Config.load()) }

    func testAppliesRedirectWhenSwitchOnAndDestinationReachable() throws {
        try sandbox.save { $0.enabled = true }
        // Launch rule: with Downloads real, the switch is turned off at start…
        daemon.start()
        XCTAssertTrue(waitUntil { !Config.load().enabled })
        XCTAssertEqual(current, .inactive)
        // …and flipping it on afterwards applies the redirect.
        try sandbox.save { $0.enabled = true }
        XCTAssertTrue(waitUntil { self.current.isActive })
        XCTAssertEqual(sandbox.linkTarget(sandbox.downloads), sandbox.destination)
        XCTAssertGreaterThanOrEqual(sandbox.helperResets, 1)
        XCTAssertTrue(waitUntil { self.sandbox.notifications.contains { $0.title == "AirDrop redirected" } })
        XCTAssertTrue(statuses.contains { $0.isActive })
    }

    func testLaunchKeepsSwitchOnWhenRedirectAlreadyInEffect() throws {
        try Redirect.apply(sandbox.config)          // e.g. left over from a crash
        try sandbox.save { $0.enabled = true }
        daemon.start()
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        XCTAssertTrue(Config.load().enabled)
        XCTAssertTrue(current.isActive)
        XCTAssertEqual(sandbox.helperResets, 0, "nothing changed, nothing to reset")
    }

    func testLaunchTurnsSwitchOffWhenDestinationUnreachable() throws {
        try Redirect.apply(sandbox.config)
        try sandbox.save { $0.enabled = true }
        try FileManager.default.removeItem(atPath: sandbox.destination)
        daemon.start()
        XCTAssertTrue(waitUntil { !Config.load().enabled && self.sandbox.isDirectory(self.sandbox.downloads) })
        XCTAssertTrue(waitUntil { self.sandbox.notifications.contains { $0.title == "AirDrop redirect switched off" && $0.body.contains("not reachable") } })
    }

    func testRestoresWhenDestinationVanishesAndReappliesWhenItReturns() throws {
        try sandbox.save { $0.enabled = false }
        daemon.start()
        try sandbox.save { $0.enabled = true }
        XCTAssertTrue(waitUntil { self.current.isActive })
        XCTAssertEqual(rename(sandbox.destination, sandbox.destination + ".gone"), 0)
        XCTAssertTrue(waitUntil { self.sandbox.isDirectory(self.sandbox.downloads) })
        XCTAssertTrue(Config.load().enabled, "switch stays on while running")
        XCTAssertTrue(waitUntil { self.sandbox.notifications.contains { $0.title == "AirDrop back to Downloads" } })
        XCTAssertEqual(rename(sandbox.destination + ".gone", sandbox.destination), 0)
        XCTAssertTrue(waitUntil { self.current.isActive })
    }

    func testSwitchOffRestores() throws {
        try sandbox.save { $0.enabled = false }
        daemon.start()
        try sandbox.save { $0.enabled = true }
        XCTAssertTrue(waitUntil { self.current.isActive })
        try sandbox.save { $0.enabled = false }
        XCTAssertTrue(waitUntil { self.current == .inactive })
        XCTAssertTrue(sandbox.exists(sandbox.downloads + "/existing.txt"))
    }

    func testReconcileNowReportsErrors() throws {
        try sandbox.save { $0.enabled = false }
        daemon.start()
        try FileManager.default.createDirectory(atPath: sandbox.parked, withIntermediateDirectories: false)   // conflict
        var reported: Error?
        var called = false
        daemon.reconcileNow { reported = $0; called = true }
        XCTAssertTrue(waitUntil { called })
        XCTAssertNotNil(reported)
        XCTAssertTrue("\(reported!)".contains("both"))
    }

    func testStopHaltsReconciliation() throws {
        try sandbox.save { $0.enabled = false }
        daemon.start()
        try sandbox.save { $0.enabled = true }
        XCTAssertTrue(waitUntil { self.current.isActive })
        daemon.stop()
        try FileManager.default.removeItem(atPath: sandbox.destination)
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        XCTAssertTrue(sandbox.isSymlink(sandbox.downloads), "nobody restored it after stop()")
    }

    func testFallbackFileIsRescuedAndSetupUnverified() throws {
        try sandbox.save { $0.enabled = false }
        daemon.start()
        try sandbox.save { $0.enabled = true }
        XCTAssertTrue(waitUntil { self.current.isActive })
        let stray = Sandbox.writeFile(sandbox.fallback + "/IMG_9.MOV", bytes: 5000)
        Sandbox.markAirDrop(stray)
        XCTAssertTrue(waitUntil(timeout: 10) { !self.events.isEmpty })
        guard case .fallback(let original, let rescuedTo, let error) = events[0] else { return XCTFail("expected fallback") }
        XCTAssertEqual(original, stray)
        XCTAssertEqual(rescuedTo, sandbox.destination + "/IMG_9.MOV")
        XCTAssertNil(error)
        XCTAssertTrue(sandbox.exists(sandbox.destination + "/IMG_9.MOV"))
        XCTAssertFalse(sandbox.exists(stray))
        XCTAssertFalse(Config.load().grantVerified)
        XCTAssertTrue(waitUntil { self.sandbox.notifications.contains { $0.title == "AirDrop needs permission" } })
        // The rescued file must not be mistaken for a genuine arrival.
        RunLoop.main.run(until: Date().addingTimeInterval(3))
        XCTAssertEqual(events.count, 1)
        XCTAssertFalse(Config.load().grantVerified)
    }

    func testGenuineArrivalMarksSetupVerified() throws {
        try sandbox.save { $0.enabled = false; $0.grantVerified = false }
        daemon.start()
        try sandbox.save { $0.enabled = true; $0.grantVerified = false }
        XCTAssertTrue(waitUntil { self.current.isActive })
        Sandbox.markAirDrop(Sandbox.writeFile(sandbox.destination + "/photo.heic"))
        XCTAssertTrue(waitUntil(timeout: 10) { !self.events.isEmpty })
        guard case .landed(let path) = events[0] else { return XCTFail("expected landed") }
        XCTAssertEqual(path, sandbox.destination + "/photo.heic")
        XCTAssertTrue(Config.load().grantVerified)
    }

    func testNoArrivalWatchingWhileInactive() throws {
        try sandbox.save { $0.enabled = false }
        daemon.start()
        Sandbox.markAirDrop(Sandbox.writeFile(sandbox.fallback + "/ignored.png"))
        RunLoop.main.run(until: Date().addingTimeInterval(3.5))
        XCTAssertTrue(events.isEmpty)
        XCTAssertTrue(sandbox.exists(sandbox.fallback + "/ignored.png"))
    }
}
