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

/// End-to-end tests that run the built `airdrop2x` executable against an isolated settings
/// directory and a fake Downloads folder.
final class CLITests: XCTestCase {
    var root = ""
    var downloads = ""
    var parked = ""
    var destination = ""

    override func setUpWithError() throws {
        root = NSTemporaryDirectory() + "airdrop2x-cli-tests/" + UUID().uuidString
        downloads = root + "/home/Downloads"
        parked = root + "/home/Downloads.local"
        destination = root + "/dest"
        for dir in [downloads, destination, root + "/cfg"] {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        // Point the CLI at the fake home before anything else.
        let seed = """
        {"downloadsFolder": "\(downloads)", "parkedFolder": "\(parked)", "grantVerified": true, "notify": false}
        """
        try seed.write(toFile: root + "/cfg/config.json", atomically: true, encoding: .utf8)
    }

    override func tearDown() {
        _ = cli(["off"])
        try? FileManager.default.removeItem(atPath: root)
    }

    private var executable: URL {
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            return bundle.bundleURL.deletingLastPathComponent().appendingPathComponent("airdrop2x")
        }
        fatalError("cannot locate the products directory")
    }

    private func cli(_ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging([
            "AIRDROP2X_CONFIG_DIR": root + "/cfg",
            "AIRDROP2X_NO_HELPER_RESET": "1",
        ]) { $1 }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try! process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }

    private func isSymlink(_ path: String) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: path)[.type] as? FileAttributeType) == .typeSymbolicLink
    }

    func testHelp() {
        let result = cli(["help"])
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("airdrop2x destination <folder>"))
        XCTAssertEqual(cli(["bogus"]).status, 1)
    }

    func testStatusWithoutDestination() {
        let result = cli(["status"])
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("destination: (not set)"))
        XCTAssertTrue(result.output.contains("OFF"))
    }

    func testOnRequiresDestination() {
        let result = cli(["on"])
        XCTAssertEqual(result.status, 2)
        XCTAssertTrue(result.output.contains("no destination chosen"))
    }

    func testDestinationValidation() {
        XCTAssertEqual(cli(["destination", root + "/missing"]).status, 1)
        XCTAssertEqual(cli(["destination", downloads]).status, 1)
        let ok = cli(["destination", destination])
        XCTAssertEqual(ok.status, 0)
        XCTAssertTrue(ok.output.contains("destination: " + destination))
        XCTAssertTrue(cli(["config"]).output.contains(destination))
    }

    func testOnOffCycle() {
        XCTAssertEqual(cli(["destination", destination]).status, 0)
        let on = cli(["on"])
        XCTAssertEqual(on.status, 0, on.output)
        XCTAssertTrue(on.output.contains("switch:      on"))
        XCTAssertTrue(on.output.contains("ON — AirDrop lands in " + destination))
        XCTAssertTrue(isSymlink(downloads))
        XCTAssertEqual(try? FileManager.default.destinationOfSymbolicLink(atPath: downloads), destination)
        XCTAssertTrue(FileManager.default.fileExists(atPath: parked))

        let status = cli(["status"])
        XCTAssertTrue(status.output.contains("reachable:   yes"))

        let off = cli(["off"])
        XCTAssertEqual(off.status, 0, off.output)
        XCTAssertTrue(off.output.contains("OFF"))
        XCTAssertFalse(isSymlink(downloads))
        XCTAssertFalse(FileManager.default.fileExists(atPath: parked))
    }

    func testOnRefusesUnreachableDestination() throws {
        XCTAssertEqual(cli(["destination", destination]).status, 0)
        try FileManager.default.removeItem(atPath: destination)
        let on = cli(["on"])
        XCTAssertEqual(on.status, 1)
        XCTAssertTrue(on.output.contains("not reachable"))
        XCTAssertFalse(isSymlink(downloads))
    }

    func testOnPrintsSetupNoteWhenNotVerified() throws {
        try #"{"downloadsFolder": "\#(downloads)", "parkedFolder": "\#(parked)", "grantVerified": false}"#
            .write(toFile: root + "/cfg/config.json", atomically: true, encoding: .utf8)
        XCTAssertEqual(cli(["destination", destination]).status, 0)
        let on = cli(["on"])
        XCTAssertEqual(on.status, 0, on.output)
        XCTAssertTrue(on.output.contains("Full Disk Access"))
    }
}
