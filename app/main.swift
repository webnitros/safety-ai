// Safety AI: тумблер режима изоляции Claude Code в строке меню.
// Включено = есть файл ~/.claude/isolation, хук ~/.claude/hooks/isolation.sh блокирует коммиты.
import AppKit

let flag = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/isolation").path

final class App: NSObject, NSApplicationDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let toggle = NSMenuItem(title: "Режим изоляции", action: #selector(flip), keyEquivalent: "")
    var on: Bool { FileManager.default.fileExists(atPath: flag) }

    func applicationDidFinishLaunching(_ n: Notification) {
        toggle.target = self
        let menu = NSMenu()
        menu.addItem(toggle)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Выход", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        refresh()
        // флаг могут поменять и из терминала, поэтому перечитываем
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
        item.button?.toolTip = on ? "Claude: коммиты запрещены" : "Claude: коммиты разрешены"
        toggle.state = on ? .on : .off
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
