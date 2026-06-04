import Cocoa

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var isActive = false

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        checkStatus()
        rebuildMenu()
    }

    // -------------------------------------------------------------------------
    // MARK: Status check
    // -------------------------------------------------------------------------

    /// Reads the current Wi-Fi DNS setting to determine if the proxy is on.
    private func checkStatus() {
        let out = shell("/usr/sbin/networksetup", ["-getdnsservers", "Wi-Fi"])
        isActive = out.contains("127.0.0.1")
    }

    // -------------------------------------------------------------------------
    // MARK: Menu
    // -------------------------------------------------------------------------

    private func rebuildMenu() {
        let menu = NSMenu()

        // Status line (non-clickable)
        let statusLine = isActive
            ? "● Active"
            : "○ Inactive"
        let infoItem = NSMenuItem(title: statusLine, action: nil, keyEquivalent: "")
        infoItem.isEnabled = false
        menu.addItem(infoItem)

        menu.addItem(.separator())

        // Toggle action
        menu.addItem(NSMenuItem(
            title: isActive ? "Turn Off" : "Turn On",
            action: #selector(toggleDNS),
            keyEquivalent: ""
        ))

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem.menu = menu

        if let btn = statusItem.button {
            let symbolName = isActive ? "shield.fill" : "shield"
            let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
            img?.isTemplate = true
            btn.image = img
        }
    }

    // -------------------------------------------------------------------------
    // MARK: Toggle
    // -------------------------------------------------------------------------

    @objc private func toggleDNS() {
        if isActive {
            sudo("/bin/launchctl",         ["stop", "com.macbyedpi.dnsredir"])
            sudo("/usr/sbin/networksetup", ["-setdnsservers", "Wi-Fi", "Empty"])
        } else {
            sudo("/bin/launchctl",         ["start", "com.macbyedpi.dnsredir"])
            sudo("/usr/sbin/networksetup", ["-setdnsservers", "Wi-Fi", "127.0.0.1"])
        }
        sudo("/usr/sbin/dscacheutil", ["-flushcache"])
        sudo("/usr/bin/killall",      ["-HUP", "mDNSResponder"])

        isActive.toggle()
        rebuildMenu()
    }

    // -------------------------------------------------------------------------
    // MARK: Helpers
    // -------------------------------------------------------------------------

    /// Runs a command via `sudo -n` (no password prompt; requires NOPASSWD sudoers entry).
    @discardableResult
    private func sudo(_ path: String, _ args: [String]) -> String {
        shell("/usr/bin/sudo", ["-n", path] + args)
    }

    @discardableResult
    private func shell(_ exe: String, _ args: [String]) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: exe)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError  = pipe
        try? task.run()
        task.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    @objc private func quitApp() { NSApp.terminate(nil) }
}

// MARK: - Entry point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
