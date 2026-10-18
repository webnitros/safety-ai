// Safety AI: menu bar toggle for Claude Code isolation mode.
// On = ~/.claude/isolation exists, and ~/.claude/hooks/isolation.sh blocks commits.
// UI language follows macOS settings; translations live in app/<lang>.lproj/Localizable.strings.
import AppKit

let flag = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/isolation").path

func t(_ key: String) -> String { NSLocalizedString(key, comment: "") }

final class App: NSObject, NSApplicationDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let toggle = NSMenuItem(title: t("Isolation mode"), action: #selector(flip), keyEquivalent: "")
    var on: Bool { FileManager.default.fileExists(atPath: flag) }

    func applicationDidFinishLaunching(_ n: Notification) {
        toggle.target = self
        let menu = NSMenu()
        menu.addItem(toggle)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: t("Quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        refresh()
        // the flag can also be changed from a terminal, so re-read it
        Timer.scheduledTimer(timeInterval: 2, target: self, selector: #selector(refresh), userInfo: nil, repeats: true)
    }

    @objc func flip() {
        if on { try? FileManager.default.removeItem(atPath: flag) }
        else { FileManager.default.createFile(atPath: flag, contents: nil) }
        refresh()
    }

    @objc func refresh() {
        let img = NSImage(systemSymbolName: on ? "lock.fill" : "lock.open", accessibilityDescription: nil)
        img?.isTemplate = true
        item.button?.image = img
        item.button?.toolTip = t(on ? "Claude: commits blocked" : "Claude: commits allowed")
        toggle.state = on ? .on : .off
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
