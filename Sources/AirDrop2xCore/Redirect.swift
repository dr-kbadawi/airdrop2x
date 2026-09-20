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

/// Makes ~/Downloads a symlink to the destination (AirDrop then writes straight there) and restores
/// the real folder when asked or when the destination becomes unreachable. Every step is idempotent
/// and refuses to overwrite anything it did not create.
public enum Redirect {
    public enum Status: Equatable {
        case active(destination: String)     // ~/Downloads -> destination, destination reachable
        case dangling(destination: String)   // ~/Downloads -> destination, but it is not reachable
        case otherLink(target: String)       // ~/Downloads is a symlink to something else
        case inactive                        // ~/Downloads is a real directory
        case missing                         // neither ~/Downloads nor the parked folder exists
        case conflict(String)                // e.g. both a real ~/Downloads and the parked folder exist

        public var isActive: Bool { if case .active = self { return true } else { return false } }
    }

    public static func status(_ config: Config) -> Status {
        let downloads = config.downloadsFolder
        let parkedExists = FileManager.default.fileExists(atPath: config.parkedFolder)
        guard let info = FileInfo(path: downloads) else {
            return parkedExists
                ? .conflict("\(downloads) is missing but \(config.parkedFolder) exists; switching off will restore it")
                : .missing
        }
        if info.isSymlink {
            let link = (try? FileManager.default.destinationOfSymbolicLink(atPath: downloads)) ?? "?"
            if let destination = config.destination, link == destination {
                return Destination.isReachable(destination) ? .active(destination: destination) : .dangling(destination: destination)
            }
            return .otherLink(target: link)
        }
        if info.isDirectory {
            return parkedExists
                ? .conflict("both \(downloads) and \(config.parkedFolder) exist; merge them by hand and delete one")
                : .inactive
        }
        return .conflict("\(downloads) is neither a directory nor a symlink")
    }

    /// Point ~/Downloads at the destination. Returns true if anything changed.
    @discardableResult
    public static func apply(_ config: Config) throws -> Bool {
        guard let destination = config.destination else { throw RedirectError("no destination chosen") }
        try Destination.check(destination)
        guard let lock = FileLock(path: Config.lockPath) else { throw RedirectError("could not take lock") }
        _ = lock
        let downloads = config.downloadsFolder
        let fm = FileManager.default

        switch status(config) {
        case .active:
            return false
        case .dangling, .otherLink:
            // Only a symlink sits at ~/Downloads; replace it.
            guard unlink(downloads) == 0 else { throw RedirectError("could not remove old symlink at \(downloads): \(errnoString())") }
            try link(destination, at: downloads)
            return true
        case .inactive:
            let hadACL = ProtectiveACL.isPresent(on: downloads)
            try ProtectiveACL.remove(from: downloads)
            guard rename(downloads, config.parkedFolder) == 0 else {
                let reason = errnoString()
                if hadACL { ProtectiveACL.add(to: downloads) }
                throw RedirectError("could not park \(downloads) as \(config.parkedFolder): \(reason)")
            }
            do {
                try link(destination, at: downloads)
            } catch {
                _ = rename(config.parkedFolder, downloads)
                if hadACL { ProtectiveACL.add(to: downloads) }
                throw error
            }
            Log.info("parked real Downloads at \(config.parkedFolder)")
            return true
        case .missing:
            throw RedirectError("\(downloads) does not exist")
        case .conflict(let why):
            // Recoverable leftover of an interrupted switch-on: the real folder is already parked and
            // only the link is missing. Anything else is a genuine conflict.
            if !fm.fileExists(atPath: downloads), fm.fileExists(atPath: config.parkedFolder) {
                try link(destination, at: downloads)
                return true
            }
            throw RedirectError(why)
        }
    }

    /// Put the real ~/Downloads back. Returns true if anything changed.
    @discardableResult
    public static func restore(_ config: Config) throws -> Bool {
        guard let lock = FileLock(path: Config.lockPath) else { throw RedirectError("could not take lock") }
        _ = lock
        let downloads = config.downloadsFolder
        let fm = FileManager.default

        switch status(config) {
        case .inactive:
            return false
        case .active, .dangling, .otherLink:
            guard unlink(downloads) == 0 else { throw RedirectError("could not remove symlink at \(downloads): \(errnoString())") }
            if fm.fileExists(atPath: config.parkedFolder) {
                guard rename(config.parkedFolder, downloads) == 0 else {
                    throw RedirectError("removed the symlink but could not move \(config.parkedFolder) back: \(errnoString())")
                }
                ProtectiveACL.add(to: downloads)
            } else {
                Log.warn("no parked folder found; creating an empty \(downloads)")
                try fm.createDirectory(atPath: downloads, withIntermediateDirectories: false)
            }
            return true
        case .missing:
            Log.warn("no Downloads folder at all; creating an empty \(downloads)")
            try fm.createDirectory(atPath: downloads, withIntermediateDirectories: false)
            return true
        case .conflict(let why):
            // The one conflict we can fix safely: only the parked folder exists.
            if !fm.fileExists(atPath: downloads), fm.fileExists(atPath: config.parkedFolder) {
                guard rename(config.parkedFolder, downloads) == 0 else { throw RedirectError("could not move \(config.parkedFolder) back: \(errnoString())") }
                ProtectiveACL.add(to: downloads)
                return true
            }
            throw RedirectError(why)
        }
    }

    private static func link(_ destination: String, at path: String) throws {
        guard symlink(destination, path) == 0 else { throw RedirectError("could not create symlink \(path) -> \(destination): \(errnoString())") }
    }

    /// sharingd's XPC helper resolves the real path of ~/Downloads once, when it launches, and keeps it
    /// for its lifetime. It is started on demand, so ending it after a switch makes the very next
    /// transfer use the new path instead of a stale one.
    public static func resetSharingHelper() {
        sharingHelperResetter()
    }

    /// What `resetSharingHelper` does. Tests replace it; AIRDROP2X_NO_HELPER_RESET=1 disables it.
    public static var sharingHelperResetter: () -> Void = {
        if ProcessInfo.processInfo.environment["AIRDROP2X_NO_HELPER_RESET"] == "1" { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        process.arguments = ["-x", "SharingXPCHelper"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    public static func describe(_ status: Status) -> String {
        switch status {
        case .active(let d):      return "ON — AirDrop lands in \(d)"
        case .dangling(let d):    return "DANGLING — ~/Downloads points at \(d) but it is not reachable"
        case .otherLink(let t):   return "~/Downloads is a symlink to \(t) (not managed by airdrop2x)"
        case .inactive:           return "OFF — AirDrop lands in the real Downloads folder"
        case .missing:            return "no Downloads folder found"
        case .conflict(let why):  return "CONFLICT — \(why)"
        }
    }
}

/// Keeps the on-disk state consistent with the switch and with the destination's reachability.
/// Re-reads the config on every pass, so changes made by another process take effect immediately.
public final class RedirectDaemon {
    private let queue = DispatchQueue(label: "airdrop2x.redirect")
    private var watchers: [Watcher] = []
    private var timer: DispatchSourceTimer?
    private var lastStatus: Redirect.Status?
    private var lastError: String?
    private var watchedDestination: String?

    /// Called on the main queue whenever the observed status changes.
    public var onStatusChange: ((Redirect.Status) -> Void)?
    /// Called on the main queue when an AirDrop item arrives while the redirect is on.
    public var onArrival: ((ArrivalEvent) -> Void)?
    private var arrivals: ArrivalWatcher?

    public enum ArrivalEvent {
        /// The item landed in the destination: the redirect works end to end.
        case landed(path: String)
        /// macOS refused sharingd access to the destination and it wrote to /private/tmp instead.
        /// The item was moved to the destination (rescuedTo) unless that failed (error).
        case fallback(original: String, rescuedTo: String?, error: String?)
    }

    /// Where sharingd writes when it may not write to Downloads. Tests point this at a temp folder.
    public static var fallbackFolder = airDropFallbackFolder

    public init() {}

    public func start() {
        var config = Config.load()
        Log.info("airdrop2x started (switch: \(config.enabled ? "on" : "off"), destination: \(config.destination ?? "none"))")
        // Launch rule: the switch may only be on if the redirect is actually in effect right now, i.e.
        // ~/Downloads already points at the destination and the destination is reachable. Otherwise the
        // switch goes off and the first reconcile pass below makes sure the real Downloads is in place.
        if config.enabled, !Redirect.status(config).isActive {
            config.enabled = false
            try? config.save()
            let reason: String
            if let destination = config.destination, !Destination.isReachable(destination) {
                reason = "\((destination as NSString).lastPathComponent) is not reachable"
            } else {
                reason = "Downloads is a real folder"
            }
            Log.info("switch turned off at launch: \(reason)")
            if config.notify { showNotification(title: "AirDrop redirect switched off", body: reason) }
        }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: config.pollSeconds)
        t.setEventHandler { [weak self] in self?.reconcile() }
        t.resume()
        timer = t
    }

    /// Stop watching. Synchronous: when this returns no further reconcile pass can run.
    public func stop() {
        queue.sync {
            timer?.cancel()
            timer = nil
            watchers.removeAll()
            arrivals?.stop()
            arrivals = nil
        }
    }

    /// While the redirect is on, watch the destination (success) and /private/tmp (fallback).
    private func syncArrivalWatcher(status: Redirect.Status, config: Config) {
        if case .active(let destination) = status {
            guard arrivals == nil else { return }
            let watcher = ArrivalWatcher(folders: [RedirectDaemon.fallbackFolder, destination], since: Date(), queue: queue) { [weak self] arrival in
                self?.handleArrival(arrival, destination: destination)
            }
            watcher.start()
            arrivals = watcher
        } else if let watcher = arrivals {
            watcher.stop()
            arrivals = nil
        }
    }

    private func handleArrival(_ arrival: ArrivalWatcher.Arrival, destination: String) {
        let name = (arrival.path as NSString).lastPathComponent
        var config = Config.load()
        let event: ArrivalEvent
        if arrival.folder == RedirectDaemon.fallbackFolder {
            Log.error("AirDrop fell back to \(RedirectDaemon.fallbackFolder) for \(name): macOS refused sharingd access to \(destination)")
            if config.grantVerified { config.grantVerified = false; try? config.save() }
            do {
                let rescued = try Rescue.move(arrival.path, toDirectory: destination)
                arrivals?.ignore(rescued)
                Log.info("rescued \(name) → \(rescued)")
                event = .fallback(original: arrival.path, rescuedTo: rescued, error: nil)
                if config.notify { showNotification(title: "AirDrop needs permission", body: "\(name) took a detour via /tmp and was moved to \((destination as NSString).lastPathComponent)") }
            } catch {
                Log.error("could not rescue \(name): \(error)")
                event = .fallback(original: arrival.path, rescuedTo: nil, error: "\(error)")
                if config.notify { showNotification(title: "AirDrop file stuck in /private/tmp", body: "\(name): \(error)") }
            }
        } else {
            Log.info("arrived: \(arrival.path)")
            if !config.grantVerified { config.grantVerified = true; try? config.save(); Log.info("setup verified: sharingd can write to the destination") }
            event = .landed(path: arrival.path)
        }
        if let handler = onArrival { DispatchQueue.main.async { handler(event) } }
    }

    /// Run a pass right away (after the user flips the switch or picks a destination).
    public func reconcileNow(completion: ((Error?) -> Void)? = nil) {
        queue.async { [weak self] in
            let error = self?.reconcile()
            if let completion = completion { DispatchQueue.main.async { completion(error) } }
        }
    }

    public var currentStatus: Redirect.Status { Redirect.status(Config.load()) }

    private func refreshWatchers(config: Config) {
        // FSEvents only lowers latency; the timer is the ground truth. Watch the destination's parent
        // (folder deleted, renamed, or its volume unmounted) and /Volumes (mounts appearing).
        guard config.destination != watchedDestination else { return }
        watchedDestination = config.destination
        watchers.removeAll()
        var paths = ["/Volumes"]
        if let destination = config.destination {
            paths.append((destination as NSString).deletingLastPathComponent)
        }
        for path in paths where FileManager.default.fileExists(atPath: path) {
            if let watcher = Watcher(path: path, queue: queue, handler: { [weak self] in _ = self?.reconcile() }) {
                watchers.append(watcher)
            }
        }
    }

    @discardableResult
    private func reconcile() -> Error? {
        let config = Config.load()
        refreshWatchers(config: config)
        let wantActive = config.enabled && Destination.isReachable(config.destination)
        var failure: Error?
        do {
            let changed = wantActive ? try Redirect.apply(config) : try Redirect.restore(config)
            lastError = nil
            let status = Redirect.status(config)
            if changed {
                Redirect.resetSharingHelper()
                Log.info("switched: \(Redirect.describe(status))")
                if config.notify {
                    switch status {
                    case .active(let d): showNotification(title: "AirDrop redirected", body: "Incoming files now land in \(d)")
                    default: showNotification(title: "AirDrop back to Downloads", body: "The destination is not reachable")
                    }
                }
            } else if lastStatus != status {
                Log.info(Redirect.describe(status))
            }
            if lastStatus != status {
                lastStatus = status
                if let handler = onStatusChange { DispatchQueue.main.async { handler(status) } }
            }
            syncArrivalWatcher(status: status, config: config)
        } catch {
            failure = error
            let text = "\(error)"
            if text != lastError {
                Log.error(text)
                lastError = text
            }
        }
        return failure
    }
}
