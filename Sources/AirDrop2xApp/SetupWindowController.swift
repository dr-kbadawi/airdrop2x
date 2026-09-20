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

import AppKit
import AirDrop2xCore

/// First-time setup guide: get /usr/libexec/sharingd into Full Disk Access, then verify with a real AirDrop.
final class SetupWindowController: NSWindowController {
    static let sharingdPath = "/usr/libexec/sharingd"
    static let fullDiskAccessPane = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"

    enum State { case instructions, testing, failed(String), success(String) }

    private let daemon: RedirectDaemon
    private let heading = NSTextField(wrappingLabelWithString: "")
    private let body = NSTextField(wrappingLabelWithString: "")
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let spinner = NSProgressIndicator()
    private let buttons = NSStackView()
    private var closeTimer: Timer?

    init(daemon: RedirectDaemon) {
        self.daemon = daemon
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 380),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "AirDrop2X — First-time Setup"
        window.level = .floating
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildLayout()
        window.center()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func buildLayout() {
        guard let content = window?.contentView else { return }
        heading.font = .boldSystemFont(ofSize: 15)
        body.font = .systemFont(ofSize: 13)
        statusLabel.font = .systemFont(ofSize: 13)
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false

        let statusRow = NSStackView(views: [spinner, statusLabel])
        statusRow.orientation = .horizontal
        statusRow.alignment = .top
        statusRow.spacing = 8

        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 12

        let stack = NSStackView(views: [heading, body, statusRow, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20),
            body.widthAnchor.constraint(equalTo: stack.widthAnchor),
            statusRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttons.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
        ])
    }

    func present(_ state: State) {
        closeTimer?.invalidate()
        apply(state)
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func apply(_ state: State) {
        let destination = Config.load().destination ?? "your folder"
        buttons.arrangedSubviews.forEach { $0.removeFromSuperview() }
        spinner.stopAnimation(nil)
        statusLabel.textColor = .secondaryLabelColor

        switch state {
        case .instructions:
            heading.stringValue = "Allow AirDrop to write outside Downloads"
            body.attributedStringValue = Self.paragraphs([
                (0, "Files you received by AirDrop are written by a macOS system process called sharingd. macOS only lets it write into the Downloads folder on the internal disk. To let it write into \(destination) instead, it needs Full Disk Access. Only you can grant that, once, in System Settings."),
                (0, ""),
                (1, "1.\tClick \"Open Full Disk Access\". System Settings opens on the right page and the path \(Self.sharingdPath) is copied to your clipboard."),
                (1, "2.\tClick the \"+\" button under the list. Then, in the file dialog:"),
                (2, "a.\tPress ⌘⇧G (Command-Shift-G) to open the \"Go to folder\" field,"),
                (2, "b.\tPress ⌘V (Command-V) to paste — the path to sharingd is already on your clipboard,"),
                (2, "c.\tPress Return (Enter) on your keyboard,"),
                (2, "d.\tFinally click \"Open\"."),
                (1, "3.\tMake sure the new \"sharingd\" entry's switch is on."),
                (1, "4.\tCome back here and click \"I've added it — test now\"."),
            ])
            statusLabel.stringValue = ""
            addButton("Cancel", #selector(cancel), key: "\u{1b}")
            addButton("Open Full Disk Access", #selector(openFullDiskAccess))
            addButton("I've added it — test now", #selector(startTest), key: "\r")

        case .testing:
            heading.stringValue = "Now send a test file"
            body.stringValue = """
            The redirect is on. AirDrop any file from your iPhone, iPad or another Mac to this Mac now. \
            A small photo is enough.

            If it lands in \(destination), setup is complete. If macOS still blocks sharingd, the file goes to \
            /private/tmp instead; AirDrop2X will move it to your folder and bring you back here.
            """
            statusLabel.stringValue = "Waiting for an AirDrop transfer…"
            spinner.startAnimation(nil)
            addButton("Cancel", #selector(cancel), key: "\u{1b}")

        case .failed(let reason):
            heading.stringValue = "macOS still blocked AirDrop from writing there"
            body.stringValue = """
            \(reason)

            Check the Full Disk Access list: the entry must be named "sharingd" (from \(Self.sharingdPath)) and its \
            switch must be on. If it is not there, add it again with the steps below, then test once more.
            """
            statusLabel.stringValue = ""
            statusLabel.textColor = .systemRed
            addButton("Cancel", #selector(cancel), key: "\u{1b}")
            addButton("Open Full Disk Access", #selector(openFullDiskAccess))
            addButton("Test again", #selector(startTest), key: "\r")

        case .success(let path):
            heading.stringValue = "It works"
            body.stringValue = "\((path as NSString).lastPathComponent) landed in \(destination). From now on every AirDrop lands there while the redirect is on. Switch it off from the menu bar whenever you want Downloads back."
            statusLabel.stringValue = ""
            statusLabel.textColor = .systemGreen
            statusLabel.stringValue = "Setup complete."
            addButton("Done", #selector(done), key: "\r")
        }
    }

    /// Paragraphs with hanging indents: level 0 plain, level 1 numbered step, level 2 sub-step.
    /// A tab after the marker lands the text on the paragraph's tab stop; wrapped lines align with it.
    private static func paragraphs(_ items: [(Int, String)]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let font = NSFont.systemFont(ofSize: 13)
        let markerWidth: CGFloat = 20
        for (index, (level, text)) in items.enumerated() {
            let style = NSMutableParagraphStyle()
            let indent = CGFloat(max(level - 1, 0)) * 24
            style.firstLineHeadIndent = level == 0 ? 0 : indent
            style.headIndent = level == 0 ? 0 : indent + markerWidth
            style.tabStops = [NSTextTab(textAlignment: .left, location: indent + markerWidth)]
            style.paragraphSpacing = 3
            let line = text + (index < items.count - 1 ? "\n" : "")
            result.append(NSAttributedString(string: line, attributes: [.font: font, .paragraphStyle: style, .foregroundColor: NSColor.labelColor]))
        }
        return result
    }

    private func addButton(_ title: String, _ action: Selector, key: String = "") {
        let button = NSButton(title: title, target: self, action: action)
        button.keyEquivalent = key
        button.bezelStyle = .rounded
        buttons.addArrangedSubview(button)
    }

    // MARK: Actions

    @objc private func openFullDiskAccess() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(Self.sharingdPath, forType: .string)
        if let url = URL(string: Self.fullDiskAccessPane) { NSWorkspace.shared.open(url) }
    }

    @objc private func startTest() {
        var config = Config.load()
        guard let destination = config.destination else { apply(.failed("No destination chosen yet. Close this window, pick a folder with \"Choose Destination…\", then switch the redirect on.")); return }
        do { try Destination.check(destination) } catch { apply(.failed("Destination not reachable: \(error). Connect the disk, then test again.")); return }
        config.enabled = true
        do { try config.save() } catch { apply(.failed("Could not save settings: \(error)")); return }
        apply(.testing)
        daemon.reconcileNow { [weak self] error in
            if let error = error { self?.apply(.failed("Could not switch the redirect on: \(error)")) }
        }
    }

    @objc private func cancel() {
        var config = Config.load()
        if !config.grantVerified {
            config.enabled = false
            try? config.save()
            daemon.reconcileNow()
        }
        close()
    }

    @objc private func done() { close() }

    /// Fed by the app delegate from the daemon's arrival events.
    func handle(_ event: RedirectDaemon.ArrivalEvent) {
        switch event {
        case .landed(let path):
            present(.success(path))
            closeTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in self?.close() }
        case .fallback(let original, let rescuedTo, let error):
            let name = (original as NSString).lastPathComponent
            var reason = rescuedTo != nil
                ? "\(name) arrived in /private/tmp and was moved to your folder for you."
                : "\(name) arrived in /private/tmp and could not be moved: \(error ?? "unknown error")."
            present(.failed(reason))
            Diagnose.recentSharingDenial { [weak self] line in
                guard let line = line else { return }
                reason += "\n\nSystem log: \(line)"
                self?.apply(.failed(reason))
            }
        }
    }
}

extension SetupWindowController: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        cancel()
        return false
    }
}
