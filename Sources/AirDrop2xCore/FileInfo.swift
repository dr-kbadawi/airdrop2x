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
