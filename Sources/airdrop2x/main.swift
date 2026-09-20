import Foundation
import AirDrop2xCore

setvbuf(stdout, nil, _IOLBF, 0)

let usage = """
airdrop2x — command-line companion to the AirDrop2x menu bar app

  airdrop2x destination <folder>  choose where AirDrop files land (any existing folder, any volume)
  airdrop2x on                    switch the redirect on
  airdrop2x off                   switch it off: the real Downloads folder is back
  airdrop2x status                show where AirDrop currently lands
  airdrop2x config                print the configuration

The menu bar app keeps the redirect consistent while it runs (restores Downloads if the destination
becomes unreachable, re-applies it when it is back). Without the app, on/off act once, immediately.
"""

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write("error: \(message)\n".data(using: .utf8)!)
    exit(code)
}

func printStatus(_ config: Config) {
    print("destination: \(config.destination ?? "(not set)")")
    print("switch:      \(config.enabled ? "on" : "off")")
    print("state:       \(Redirect.describe(Redirect.status(config)))")
    if let destination = config.destination {
        do { try Destination.check(destination); print("reachable:   yes") }
        catch { print("reachable:   no (\(error))") }
    }
}

var args = Array(CommandLine.arguments.dropFirst())
let command = args.first ?? "help"
if !args.isEmpty { args.removeFirst() }

switch command {
case "destination", "target":
    guard let raw = args.first else { fail("usage: airdrop2x destination <folder>") }
    let path = normalizePath(raw)
    var config = Config.load()
    do { try Destination.validateChoice(path, config: config) } catch { fail("\(error)") }
    config.destination = path
    do { try config.save() } catch { fail("could not save config: \(error)") }
    if config.enabled {
        do { if try Redirect.apply(config) { Redirect.resetSharingHelper() } } catch { fail("\(error)") }
    }
    printStatus(config)

case "on":
    var config = Config.load()
    guard let destination = config.destination else { fail("no destination chosen. Run: airdrop2x destination <folder>", code: 2) }
    config.enabled = true
    do { try config.save() } catch { fail("could not save config: \(error)") }
    do {
        try Destination.check(destination)
        if try Redirect.apply(config) { Redirect.resetSharingHelper() }
    } catch { fail("\(error)") }
    if !config.grantVerified {
        print("note: one-time setup: macOS lets AirDrop (sharingd) write outside Downloads only after")
        print("      /usr/libexec/sharingd is added to Full Disk Access in System Settings > Privacy & Security.")
        print("      The menu bar app guides you through this and rescues any file that falls back to /private/tmp.")
    }
    printStatus(config)

case "off":
    var config = Config.load()
    config.enabled = false
    do { try config.save() } catch { fail("could not save config: \(error)") }
    do { if try Redirect.restore(config) { Redirect.resetSharingHelper() } } catch { fail("\(error)") }
    printStatus(config)

case "status":
    printStatus(Config.load())

case "config":
    print(Config.load().describe())

default:
    print(usage)
    exit(["help", "--help", "-h"].contains(command) ? 0 : 1)
}
