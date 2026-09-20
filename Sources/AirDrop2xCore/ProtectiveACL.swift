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

/// macOS puts `group:everyone deny delete` on the standard home folders (Downloads, Desktop, …) so
/// they cannot be deleted or renamed by accident. Renaming needs delete permission, so the entry
/// must be lifted while ~/Downloads is parked and put back when it is restored.
enum ProtectiveACL {
    static let entry = "group:everyone deny delete"

    static func isPresent(on path: String) -> Bool {
        let (status, output) = run("/bin/ls", ["-lde", path])
        return status == 0 && output.contains("everyone deny delete")
    }

    static func remove(from path: String) throws {
        guard isPresent(on: path) else { return }
        let (status, output) = run("/bin/chmod", ["-a", entry, path])
        guard status == 0 else { throw RedirectError("could not lift the protective ACL on \(path): \(output.trimmingCharacters(in: .whitespacesAndNewlines))") }
    }

    static func add(to path: String) {
        guard !isPresent(on: path) else { return }
        let (status, output) = run("/bin/chmod", ["+a", entry, path])
        if status != 0 { Log.warn("could not re-add the protective ACL on \(path): \(output)") }
    }

    private static func run(_ tool: String, _ arguments: [String]) -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (-1, "\(error)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
