import Foundation

public struct Config: Codable {
    /// Folder AirDrop should deliver into. Any writable directory on any volume. Never created by us.
    public var destination: String?
    /// The folder macOS hardcodes as the AirDrop destination.
    public var downloadsFolder: String = NSHomeDirectory() + "/Downloads"
    /// Where the real Downloads directory is parked while the redirect is active.
    public var parkedFolder: String = NSHomeDirectory() + "/Downloads.local"
    /// The user's switch: keep ~/Downloads pointing at the destination whenever it is reachable.
    public var enabled: Bool = false
    /// How often the destination's reachability is re-checked.
    public var pollSeconds: Double = 2
    /// Show a macOS notification whenever the redirect switches on or off by itself.
    public var notify: Bool = true
    /// A file has been seen arriving in the destination: the one-time Full Disk Access setup for sharingd is done.
    public var grantVerified: Bool = false

    public static let directory = ProcessInfo.processInfo.environment["AIRDROP2X_CONFIG_DIR"]
        ?? NSHomeDirectory() + "/Library/Application Support/airdrop2x"
    public static let path = directory + "/config.json"
    public static let lockPath = directory + "/lock"

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        destination     = try c.decodeIfPresent(String.self, forKey: .destination) ?? d.destination
        downloadsFolder = try c.decodeIfPresent(String.self, forKey: .downloadsFolder) ?? d.downloadsFolder
        parkedFolder    = try c.decodeIfPresent(String.self, forKey: .parkedFolder) ?? d.parkedFolder
        enabled         = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        pollSeconds     = try c.decodeIfPresent(Double.self, forKey: .pollSeconds) ?? d.pollSeconds
        notify          = try c.decodeIfPresent(Bool.self, forKey: .notify) ?? d.notify
        grantVerified   = try c.decodeIfPresent(Bool.self, forKey: .grantVerified) ?? d.grantVerified
    }

    public static func load() -> Config {
        guard let data = FileManager.default.contents(atPath: path) else { return Config() }
        do {
            return try JSONDecoder().decode(Config.self, from: data)
        } catch {
            Log.warn("config at \(path) is unreadable (\(error)); using defaults")
            return Config()
        }
    }

    public func save() throws {
        try FileManager.default.createDirectory(atPath: Config.directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: URL(fileURLWithPath: Config.path), options: .atomic)
    }

    public func describe() -> String {
        """
        config file:       \(Config.path)
        destination:       \(destination ?? "(not set)")
        switch:            \(enabled ? "on" : "off")
        downloads folder:  \(downloadsFolder)
        parked folder:     \(parkedFolder)
        poll seconds:      \(pollSeconds)
        notify:            \(notify)
        grant verified:    \(grantVerified)
        """
    }
}

/// Expand ~ and make absolute + standardized.
public func normalizePath(_ raw: String) -> String {
    let expanded = (raw as NSString).expandingTildeInPath
    let absolute = expanded.hasPrefix("/") ? expanded : FileManager.default.currentDirectoryPath + "/" + expanded
    return (absolute as NSString).standardizingPath
}

/// Exclusive advisory lock so two processes never rearrange ~/Downloads at the same time.
final class FileLock {
    private let fd: Int32
    init?(path: String) {
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        fd = open(path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0, flock(fd, LOCK_EX) == 0 else { if fd >= 0 { close(fd) }; return nil }
    }
    deinit { flock(fd, LOCK_UN); close(fd) }
}
