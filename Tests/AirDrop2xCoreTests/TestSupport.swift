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

import Foundation
import XCTest
@testable import AirDrop2xCore

/// An isolated file tree and settings directory for one test: a fake home with Downloads, a
/// destination, a fallback folder standing in for /private/tmp, and captured side effects.
final class Sandbox {
    let root: String
    let downloads: String
    let parked: String
    let destination: String
    let fallback: String
    private(set) var notifications: [(title: String, body: String)] = []
    private(set) var helperResets = 0

    init() throws {
        root = NSTemporaryDirectory() + "airdrop2x-tests/" + UUID().uuidString
        downloads = root + "/home/Downloads"
        parked = root + "/home/Downloads.local"
        destination = root + "/dest"
        fallback = root + "/fallback"
        for directory in [downloads, destination, fallback, root + "/cfg"] {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }
        try "existing".write(toFile: downloads + "/existing.txt", atomically: true, encoding: .utf8)
        Config.directory = root + "/cfg"
        Notifier.sink = { [weak self] title, body in self?.notifications.append((title, body)) }
        Redirect.sharingHelperResetter = { [weak self] in self?.helperResets += 1 }
        RedirectDaemon.fallbackFolder = fallback
    }

    /// A config pointing at this sandbox, switch off, setup verified, fast polling.
    var config: Config {
        var config = Config()
        config.downloadsFolder = downloads
        config.parkedFolder = parked
        config.destination = destination
        config.notify = true
        config.pollSeconds = 0.2
        config.grantVerified = true
        return config
    }

    func save(_ mutate: (inout Config) -> Void = { _ in }) throws {
        var config = self.config
        mutate(&config)
        try config.save()
    }

    func tearDown() {
        try? Redirect.restore(config)
        try? FileManager.default.removeItem(atPath: root)
        Notifier.sink = nil
        Redirect.sharingHelperResetter = {}
    }

    // MARK: File helpers

    func isSymlink(_ path: String) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: path)[.type] as? FileAttributeType) == .typeSymbolicLink
    }

    func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue && !isSymlink(path)
    }

    func linkTarget(_ path: String) -> String? {
        try? FileManager.default.destinationOfSymbolicLink(atPath: path)
    }

    func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }

    @discardableResult
    static func writeFile(_ path: String, bytes: Int = 1024) -> String {
        FileManager.default.createFile(atPath: path, contents: Data(repeating: 0x41, count: bytes))
        return path
    }

    static func markAirDrop(_ path: String) {
        let value = "0081;\(String(UInt64(Date().timeIntervalSince1970), radix: 16));sharingd;00000000-0000-0000-0000-000000000000"
        _ = value.withCString { setxattr(path, "com.apple.quarantine", $0, strlen($0), 0, 0) }
    }

    static func markQuarantine(_ path: String, agent: String) {
        let value = "0081;0;\(agent);00000000-0000-0000-0000-000000000000"
        _ = value.withCString { setxattr(path, "com.apple.quarantine", $0, strlen($0), 0, 0) }
    }

    static func addDenyDeleteACL(_ path: String) {
        run("/bin/chmod", ["+a", "group:everyone deny delete", path])
    }

    static func hasDenyDeleteACL(_ path: String) -> Bool {
        run("/bin/ls", ["-lde", path]).contains("everyone deny delete")
    }

    @discardableResult
    static func run(_ tool: String, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try? process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// Spin the main run loop until `condition` holds or `timeout` passes.
@discardableResult
func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    return condition()
}
