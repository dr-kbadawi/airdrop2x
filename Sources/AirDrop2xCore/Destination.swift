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

public struct RedirectError: Error, CustomStringConvertible {
    public let description: String
    public init(_ text: String) { description = text }
}

public enum Destination {
    /// The destination is usable when it is an existing, writable directory. Where it lives does not
    /// matter: boot disk, another partition, external drive, network share, disk image.
    /// One guard applies to paths under /Volumes: the volume must actually be mounted, so a stand-in
    /// directory left behind after an unmount is never mistaken for the real destination.
    public static func check(_ path: String) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw RedirectError("destination is not reachable: \(path)")
        }
        if path.hasPrefix("/Volumes/") {
            let components = path.split(separator: "/", omittingEmptySubsequences: true)
            if components.count >= 2 {
                let volumeRoot = "/Volumes/" + components[1]
                guard let volume = FileInfo(path: volumeRoot, followSymlinks: true),
                      let volumes = FileInfo(path: "/Volumes", followSymlinks: true),
                      volume.device != volumes.device else {
                    throw RedirectError("\(volumeRoot) is not mounted")
                }
            }
        }
        guard FileManager.default.isWritableFile(atPath: path) else {
            throw RedirectError("destination is not writable: \(path)")
        }
    }

    /// Rules a user-chosen destination must satisfy before it is saved.
    public static func validateChoice(_ path: String, config: Config) throws {
        let downloads = config.downloadsFolder
        if path == downloads || path.hasPrefix(downloads + "/") {
            throw RedirectError("the destination cannot be the Downloads folder or something inside it")
        }
        if path == config.parkedFolder || path.hasPrefix(config.parkedFolder + "/") {
            throw RedirectError("the destination cannot be inside \(config.parkedFolder)")
        }
        try check(path)
    }

    public static func isReachable(_ path: String?) -> Bool {
        guard let path = path else { return false }
        return (try? check(path)) != nil
    }
}
