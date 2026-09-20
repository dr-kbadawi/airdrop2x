import Foundation

/// The folder sharingd falls back to when it may not write to the Downloads folder.
public let airDropFallbackFolder = "/private/tmp"

/// Notices AirDrop-delivered items (quarantine agent "sharingd") appearing in a set of folders after
/// `since`, and reports each one once its size has been stable for two seconds.
final class ArrivalWatcher {
    struct Arrival { let path: String; let folder: String }

    private let folders: [String]
    private let since: Date
    private let queue: DispatchQueue
    private let handler: (Arrival) -> Void
    private var watchers: [Watcher] = []
    private var timer: DispatchSourceTimer?
    private var pending: [String: (size: Int64, seenAt: Date)] = [:]
    private var reported = Set<String>()

    init(folders: [String], since: Date, queue: DispatchQueue, handler: @escaping (Arrival) -> Void) {
        self.folders = folders
        self.since = since
        self.queue = queue
        self.handler = handler
    }

    func start() {
        for folder in folders where FileManager.default.fileExists(atPath: folder) {
            if let w = Watcher(path: folder, queue: queue, handler: { [weak self] in self?.scan() }) { watchers.append(w) }
        }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1, repeating: 1)
        t.setEventHandler { [weak self] in self?.scan() }
        t.resume()
        timer = t
    }

    /// Items we moved ourselves must not count as arrivals. Call on the watcher's queue.
    func ignore(_ path: String) {
        reported.insert(path)
        pending.removeValue(forKey: path)
    }

    func stop() {
        timer?.cancel()
        timer = nil
        watchers.removeAll()
    }

    private func scan() {
        let now = Date()
        for folder in folders {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder) else { continue }
            for name in names where !name.hasPrefix(".") {
                let path = folder + "/" + name
                guard !reported.contains(path), let info = FileInfo(path: path), info.isRegular || info.isDirectory else { continue }
                // ctime also moves when the item is renamed into place or its quarantine tag is written.
                guard info.created >= since.addingTimeInterval(-1) || info.changed >= since.addingTimeInterval(-1) else { continue }
                guard Quarantine.isAirDrop(path) else { continue }
                if let seen = pending[path], seen.size == info.size {
                    if now.timeIntervalSince(seen.seenAt) >= 2 {
                        reported.insert(path)
                        pending.removeValue(forKey: path)
                        handler(Arrival(path: path, folder: folder))
                    }
                } else {
                    pending[path] = (info.size, now)
                }
            }
        }
    }
}

enum Rescue {
    /// Move an item that fell back to /private/tmp into the destination, keeping its name.
    static func move(_ path: String, toDirectory destination: String) throws -> String {
        try Destination.check(destination)
        let name = (path as NSString).lastPathComponent
        let target = uniqueDestination(directory: destination, name: name)
        try FileManager.default.moveItem(atPath: path, toPath: target)   // copies across volumes, then deletes
        return target
    }

    static func uniqueDestination(directory: String, name: String) -> String {
        let fm = FileManager.default
        var candidate = directory + "/" + name
        guard fm.fileExists(atPath: candidate) else { return candidate }
        let ns = name as NSString
        let ext = ns.pathExtension
        let stem = ext.isEmpty ? name : ns.deletingPathExtension
        var n = 2
        repeat {
            candidate = directory + "/" + (ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)")
            n += 1
        } while fm.fileExists(atPath: candidate)
        return candidate
    }
}

public enum Diagnose {
    /// Looks in the unified log for the kernel line that records macOS refusing sharingd's helper
    /// access to the destination. Calls back on the main queue with the line, or nil if none was found.
    public static func recentSharingDenial(completion: @escaping (String?) -> Void) {
        DispatchQueue.global().async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
            process.arguments = ["show", "--last", "5m", "--style", "compact",
                                 "--predicate", "process == \"kernel\" AND eventMessage CONTAINS \"SharingXPCHelper\" AND eventMessage CONTAINS \"file-issue-extension\""]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            var line: String?
            if (try? process.run()) != nil {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let lines = (String(data: data, encoding: .utf8) ?? "").split(separator: "\n").map(String.init)
                line = lines.last { $0.contains("deny") }
            }
            DispatchQueue.main.async { completion(line) }
        }
    }
}
