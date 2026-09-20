import AppKit
import ServiceManagement
import AirDrop2xCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let daemon = RedirectDaemon()
    private var status: Redirect.Status = .inactive
    private lazy var setup = SetupWindowController(daemon: daemon)
    private var menuIsOpen = false
    private var reminder: Timer?
    private var reminderShowing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.filePath = NSHomeDirectory() + "/Library/Logs/airdrop2x.log"
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        status = daemon.currentStatus
        updateIcon()
        daemon.onStatusChange = { [weak self] status in
            self?.status = status
            self?.updateIcon()
            self?.refreshMenuIfOpen()
            self?.syncReminder()
        }
        daemon.onArrival = { [weak self] event in self?.handleArrival(event) }
        daemon.start()
    }

    /// Quitting means nobody is watching the destination any more, so put the real Downloads back.
    /// The switch itself stays as the user left it and is re-applied at the next launch.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        daemon.stop()   // otherwise a pass could re-apply the redirect between restore and exit
        let config = Config.load()
        if Redirect.status(config) != .inactive {
            do {
                if try Redirect.restore(config) {
                    Redirect.resetSharingHelper()
                    Log.info("restored Downloads on quit")
                }
            } catch {
                Log.error("could not restore Downloads on quit: \(error)")
            }
        }
        return .terminateNow
    }

    // MARK: Reminder — people forget the redirect on, so ask periodically while it is active.

    private func syncReminder() {
        let minutes = Config.load().reminderMinutes
        if status.isActive, minutes > 0 {
            if reminder == nil { scheduleReminder(minutes: minutes) }
        } else {
            reminder?.invalidate()
            reminder = nil
        }
    }

    private func scheduleReminder(minutes: Double) {
        reminder?.invalidate()
        let timer = Timer(timeInterval: minutes * 60, repeats: false) { [weak self] _ in self?.askToKeepOn() }
        RunLoop.main.add(timer, forMode: .common)   // fires even while a menu is open
        reminder = timer
    }

    private func askToKeepOn() {
        reminder = nil
        guard status.isActive, !reminderShowing else { return }
        let config = Config.load()
        guard let destination = config.destination else { return }
        reminderShowing = true
        Log.info("reminder: asking whether to keep the redirect on")
        statusItem.menu?.cancelTracking()
        let choice = Dialog.show(title: "AirDrop is still being redirected",
                                 text: "Files you receive by AirDrop are landing in \(shortPath(destination)), not in Downloads.\n\nKeep redirecting?",
                                 symbol: "arrow.turn.down.right", tint: .systemGreen,
                                 buttons: ["Done, switch it off", "Yes, keep it on"])
        reminderShowing = false
        if choice == 0 {
            setRedirect(false)
        } else if status.isActive, config.reminderMinutes > 0 {
            scheduleReminder(minutes: config.reminderMinutes)
        }
    }

    // MARK: Menu

    func menuWillOpen(_ menu: NSMenu) { menuIsOpen = true }
    func menuDidClose(_ menu: NSMenu) { menuIsOpen = false }

    /// Rebuild the rows of the open menu so a flipped switch, the status line and its color update live.
    private func refreshMenuIfOpen() {
        guard menuIsOpen, let menu = statusItem.menu else { return }
        menuNeedsUpdate(menu)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let config = Config.load()
        status = Redirect.status(config)
        updateIcon()
        let smStatus = SMAppService.mainApp.status
        let model = MenuModel.make(config: config, status: status,
                                   login: smStatus == .enabled ? .enabled : (smStatus == .requiresApproval ? .requiresApproval : .disabled))

        menu.autoenablesItems = false
        let headline = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        headline.attributedTitle = NSAttributedString(string: model.headline, attributes: [
            .foregroundColor: Self.color(for: model.tone),
            .font: NSFont.menuFont(ofSize: 0),
        ])
        headline.isEnabled = true   // enabled so the color shows; it has no action
        menu.addItem(headline)
        if let detail = model.detail {
            let item = NSMenuItem(title: detail, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        if let line = model.destinationLine {
            let row = DestinationMenuItemView(path: String(line.dropFirst("Destination: ".count)))
            row.onClear = { [weak self] in self?.clearDestination() }
            let item = NSMenuItem(title: "Destination", action: nil, keyEquivalent: "")
            item.view = row
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let switchRow = SwitchMenuItemView(title: "Redirect AirDrop", isOn: model.switchOn, isEnabled: model.switchEnabled)
        switchRow.onChange = { [weak self] on in self?.setRedirect(on) }
        let switchItem = NSMenuItem(title: "Redirect AirDrop", action: nil, keyEquivalent: "")
        switchItem.view = switchRow
        menu.addItem(switchItem)

        let choose = NSMenuItem(title: model.chooseTitle, action: #selector(chooseDestination), keyEquivalent: "")
        choose.target = self
        menu.addItem(choose)

        let setupItem = NSMenuItem(title: model.setupTitle, action: #selector(showSetup), keyEquivalent: "")
        setupItem.target = self
        menu.addItem(setupItem)

        if let destination = config.destination {
            let reveal = NSMenuItem(title: "Show Destination in Finder", action: #selector(revealDestination), keyEquivalent: "")
            reveal.target = self
            reveal.isEnabled = Destination.isReachable(destination)
            menu.addItem(reveal)
        }
        menu.addItem(.separator())

        let loginRow = SwitchMenuItemView(title: model.loginTitle, isOn: model.loginOn, isEnabled: true)
        loginRow.onChange = { [weak self] on in self?.setLoginItem(on) }
        let login = NSMenuItem(title: "Start at Login", action: nil, keyEquivalent: "")
        login.view = loginRow
        menu.addItem(login)

        let about = NSMenuItem(title: "About AirDrop2X…", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(title: "Quit AirDrop2X", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        quit.toolTip = "Quitting restores the real Downloads folder"
        menu.addItem(quit)
    }

    static func color(for tone: MenuModel.Tone) -> NSColor {
        switch tone {
        case .active: return .systemGreen
        case .idle:   return .systemOrange
        case .none:   return .systemGray
        }
    }

    private func shortPath(_ path: String) -> String { MenuModel.shortPath(path) }

    private func updateIcon() {
        let config = Config.load()
        let tone: MenuModel.Tone = config.destination == nil ? .none : (status.isActive ? .active : .idle)
        statusItem.button?.image = StatusGlyph.image(color: Self.color(for: tone))
        statusItem.button?.toolTip = Redirect.describe(status)
    }

    // MARK: Actions

    private func setRedirect(_ on: Bool) {
        var config = Config.load()
        guard config.enabled != on else { return }
        if on, let destination = config.destination {
            do {
                try Destination.check(destination)
            } catch {
                statusItem.menu?.cancelTracking()
                let name = (destination as NSString).lastPathComponent
                let choice = alert("“\(name)” is not reachable right now",
                                   "AirDrop2X cannot redirect to \(shortPath(destination)).\n\nIf it is on an external disk or a network share, connect it and switch on again. Or pick a different folder.",
                                   symbol: "externaldrive.badge.xmark", buttons: ["OK", "Choose Another Folder…"])
                if choice == 1 { chooseDestination() }
                refreshMenuIfOpen()
                return
            }
        }
        if on, !config.grantVerified {
            statusItem.menu?.cancelTracking()
            setup.present(.instructions)   // switches on itself once the user starts the test
            return
        }
        config.enabled = on
        do { try config.save() } catch { alert("Could not save settings", "\(error)"); return }
        daemon.reconcileNow { [weak self] error in
            if let error = error {
                self?.statusItem.menu?.cancelTracking()
                self?.alert(on ? "Could not redirect AirDrop" : "Could not restore Downloads", "\(error)")
            }
            self?.refreshMenuIfOpen()
        }
    }

    @objc private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.title = "Choose where AirDrop files should land"
        panel.message = "Any folder on any disk or volume. It must already exist."
        panel.prompt = "Use This Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if let current = Config.load().destination, Destination.isReachable(current) {
            panel.directoryURL = URL(fileURLWithPath: current)
        }
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        var config = Config.load()
        let path = normalizePath(url.path)
        do { try Destination.validateChoice(path, config: config) } catch { alert("This folder cannot be used", "\(error)"); return }
        config.destination = path
        do { try config.save() } catch { alert("Could not save settings", "\(error)"); return }
        daemon.reconcileNow { [weak self] error in
            if let error = error { self?.alert("Could not apply the new destination", "\(error)") }
        }
        if config.enabled, !config.grantVerified { setup.present(.instructions) }
    }

    /// Forget the destination. If the redirect is on, switch it off first so Downloads is restored.
    private func clearDestination() {
        var config = Config.load()
        let wasOn = config.enabled
        config.enabled = false
        config.destination = nil
        do { try config.save() } catch { alert("Could not save settings", "\(error)"); return }
        if wasOn {
            daemon.reconcileNow { [weak self] error in
                if let error = error {
                    self?.statusItem.menu?.cancelTracking()
                    self?.alert("Could not restore Downloads", "\(error)")
                }
                self?.refreshMenuIfOpen()
            }
        } else {
            refreshMenuIfOpen()
        }
    }

    @objc private func showSetup() {
        statusItem.menu?.cancelTracking()
        setup.present(.instructions)
    }

    private func handleArrival(_ event: RedirectDaemon.ArrivalEvent) {
        switch event {
        case .landed(let path):
            if setup.window?.isVisible == true { setup.handle(event) }
            else if Config.load().notify { showNotification(title: "AirDrop file arrived", body: (path as NSString).lastPathComponent) }
        case .fallback:
            setup.handle(event)   // always bring the guide up: the permission is missing or was reset
        }
    }

    @objc private func revealDestination() {
        guard let destination = Config.load().destination else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: destination)])
    }

    private func setLoginItem(_ on: Bool) {
        let service = SMAppService.mainApp
        do {
            if !on {
                if service.status == .enabled || service.status == .requiresApproval { try service.unregister() }
            } else if service.status == .requiresApproval {
                statusItem.menu?.cancelTracking()
                SMAppService.openSystemSettingsLoginItems()
            } else if service.status != .enabled {
                try service.register()
                if service.status == .requiresApproval {
                    statusItem.menu?.cancelTracking()
                    alert("One more step", "macOS wants you to approve AirDrop2X under Login Items in System Settings. The page opens when you close this.")
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        } catch {
            statusItem.menu?.cancelTracking()
            alert("Could not change the login item", "\(error.localizedDescription)\n\nMake sure the app is in the Applications folder.")
        }
        refreshMenuIfOpen()
    }

    @objc private func showAbout() {
        statusItem.menu?.cancelTracking()
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        let copyright = info["NSHumanReadableCopyright"] as? String ?? ""
        let icon = NSApp.applicationIconImage
        icon?.size = NSSize(width: 72, height: 72)
        Dialog.show(title: "AirDrop2X",
                    text: """
                    Version \(version) (\(build))

                    Makes AirDrop deliver files straight into a folder of your choosing, on any disk or volume. \
                    Switch it on, AirDrop lands there. Switch it off, Downloads is back to normal.

                    \(copyright)
                    Free software, released under the GNU General Public License v3.0.
                    """,
                    image: icon)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    /// Centered dialog with a symbol; returns the index of the clicked button.
    @discardableResult
    private func alert(_ title: String, _ text: String, symbol: String = "exclamationmark.triangle.fill", buttons: [String] = ["OK"]) -> Int {
        Dialog.show(title: title, text: text, symbol: symbol, buttons: buttons)
    }
}
