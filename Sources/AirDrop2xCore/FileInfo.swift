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

struct FileInfo {
    let isDirectory: Bool
    let isSymlink: Bool
    let isRegular: Bool
    let size: Int64
    let created: Date
    let changed: Date
    let device: dev_t

    init?(path: String, followSymlinks: Bool = false) {
        var st = stat()
        let rc = followSymlinks ? stat(path, &st) : lstat(path, &st)
        guard rc == 0 else { return nil }
        let type = st.st_mode & S_IFMT
        isDirectory = type == S_IFDIR
        isSymlink = type == S_IFLNK
        isRegular = type == S_IFREG
        size = Int64(st.st_size)
        created = Date(timeIntervalSince1970: TimeInterval(st.st_birthtimespec.tv_sec))
        changed = Date(timeIntervalSince1970: TimeInterval(st.st_ctimespec.tv_sec))
        device = st.st_dev
    }
}

/// com.apple.quarantine = "flags;hex-unix-time;agent;uuid". AirDrop-received items carry agent "sharingd".
enum Quarantine {
    static func agent(of path: String) -> String? {
        let name = "com.apple.quarantine"
        let needed = getxattr(path, name, nil, 0, 0, XATTR_NOFOLLOW)
        guard needed > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: needed)
        let got = getxattr(path, name, &buffer, needed, 0, XATTR_NOFOLLOW)
        guard got > 0, let text = String(bytes: buffer[0..<got], encoding: .utf8) else { return nil }
        let parts = text.split(separator: ";", omittingEmptySubsequences: false)
        return parts.count >= 3 ? String(parts[2]) : nil
    }

    static func isAirDrop(_ path: String) -> Bool { agent(of: path) == "sharingd" }
}
