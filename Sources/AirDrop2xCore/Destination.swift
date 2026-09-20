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
