import AppKit

// Only one instance may run, or the menu bar gets duplicate status items and
// menu bar managers (Thaw, Ice, Hidden Bar) see several identities for one app.
let others = NSRunningApplication
    .runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "local.toolsspecter")
    .filter { $0.processIdentifier != getpid() }
if !others.isEmpty {
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
