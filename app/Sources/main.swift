import AppKit

// Single-instance guard. Two copies with the same bundle ID (e.g. the
// ~/workspace build and the /Applications install) each install their own
// global event tap, so every dictation would be recorded — and pasted — twice.
// If another instance is already running, hand off to it and exit.
let bundleID = Bundle.main.bundleIdentifier ?? "dev.yun.localwillow"
let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
if let existing = others.first {
    Log.write("launch: another instance (pid \(existing.processIdentifier)) already running — exiting")
    existing.activate(options: [])
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)  // menu bar only, no Dock icon
app.run()
