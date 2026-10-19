// Safety AI: menu bar app and settings window for Claude Code isolation mode.
// State lives in ~/Library/Application Support/Safety AI: flag "isolation" (on/off), "rules.conf", hook "isolation.sh".
// UI language follows macOS settings; translations live in app/<lang>.lproj/Localizable.strings.
import AppKit
import Combine
import SwiftUI

let home = FileManager.default.homeDirectoryForCurrentUser.path
let stateDir = home + "/Library/Application Support/Safety AI"
let flag = stateDir + "/isolation"
let conf = stateDir + "/rules.conf"
let claudeSettings = home + "/.claude/settings.json"
let loginAgent = home + "/Library/LaunchAgents/local.safety-ai.plist"
// built-in rules the hook knows, in display order
let rules: [(key: String, title: String, detail: String)] = [
    ("commit", "Commits", "git commit, am, cherry-pick · GitLab add_commit"),
    ("push", "Push & new branches", "git push, gh repo create/sync · GitLab add_branch"),
    ("merge", "Merge & rebase", "git merge, git rebase"),
    ("tag", "Tags & releases", "git tag, gh release create"),
    ("pr", "Pull / merge requests", "gh pr create/merge · GitLab merge requests"),
]
// ready-made custom rules for the "Add example" menu; " +" in a regex means one or more spaces
let examples: [(re: String, what: String)] = [
    ("rm +-[a-z]*r", "example.rm"),
    ("git +reset +--hard", "example.reset"),
    ("git +clean +-[a-z]*f", "example.clean"),
    ("docker +compose +down", "example.compose"),
    ("docker +(rm|rmi|volume +rm|system +prune)", "example.docker"),
    ("kubectl +delete", "example.kubectl"),
    ("(DROP|drop|TRUNCATE|truncate) +(TABLE|table|DATABASE|database)", "example.sql"),
    ("(npm|yarn|pnpm) +publish", "example.publish"),
    ("(^|[;&|] *)ssh( |$)", "example.ssh"),
]
let header = """
# Safety AI rules, written by the app (Settings window). One per line:
#   commit, push, merge, tag, pr   built-in rules
#   ask                            show an Allow / Deny dialog instead of blocking
#   deny <regex>                   your own rule, matched against shell commands the agent runs

"""

func t(_ key: String) -> String { NSLocalizedString(key, comment: "") }

struct Config: Equatable {
    var enabled: Set<String>  // rule keys + "ask"
    var deny: [String]

    // no file yet = all built-in rules on, which is also what the hook assumes
    static func load() -> Config {
        guard let s = try? String(contentsOfFile: conf, encoding: .utf8) else {
            return Config(enabled: Set(rules.map(\.key)), deny: [])
        }
        let lines = s.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        return Config(
            enabled: Set(lines.filter { !$0.hasPrefix("#") && !$0.hasPrefix("deny ") }),
            deny: lines.filter { $0.hasPrefix("deny ") }.map { $0.dropFirst(5).trimmingCharacters(in: .whitespaces) })
    }

    func save() {
        try? FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)
        let keys = (rules.map(\.key) + ["ask"]).filter(enabled.contains)
        let body = header + (keys + deny.map { "deny " + $0 }).joined(separator: "\n") + "\n"
        try? body.write(toFile: conf, atomically: true, encoding: .utf8)
    }
}

// how long isolation stays on, in minutes; 0 = until turned off
let durations = [0, 15, 30, 60, 120, 240, 480]

func hoursMinutes(_ seconds: TimeInterval) -> String {
    let f = DateComponentsFormatter()
    f.unitsStyle = .short
    f.allowedUnits = [.hour, .minute]
    return f.string(from: seconds) ?? ""
}

func durationTitle(_ minutes: Int) -> String {
    minutes == 0 ? t("Until turned off") : hoursMinutes(TimeInterval(minutes * 60))
}

// rounded up to whole minutes, so "1 min" shows until the very end
func remainingTitle(_ until: Date) -> String {
    String(format: t("%@ left"), hoursMinutes(max(60, (until.timeIntervalSinceNow / 60).rounded(.up) * 60)))
}

final class Model: ObservableObject {
    @Published var on = false
    @Published var until: Date? = nil  // end of timed isolation, nil = until turned off
    @Published var duration = UserDefaults.standard.integer(forKey: "duration")
    @Published var config = Config.load()
    @Published var denyText = ""
    @Published var hookInstalled = true
    @Published var tab = "rules"
    @Published var autostart = FileManager.default.fileExists(atPath: loginAgent)

    // flag and config can also be changed from a terminal, so this runs on a timer
    func reload() {
        let isOn = FileManager.default.fileExists(atPath: flag)
        var end: Date? = nil
        if isOn, let s = try? String(contentsOfFile: flag, encoding: .utf8),
           let secs = Double(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
            end = Date(timeIntervalSince1970: secs)
        }
        // time is up: the hook already ignores the flag, remove it so the UI agrees
        if let e = end, e <= Date() { turnOff(); return }
        if isOn != on { on = isOn }
        if end != until { until = end }
        let c = Config.load()
        if c != config { config = c }
        let hook = registered(in: claudeSettings)
        if hook != hookInstalled { hookInstalled = hook }
    }

    func registered(in file: String) -> Bool {
        (try? String(contentsOfFile: file, encoding: .utf8))?.contains("Safety AI/isolation.sh") == true
    }

    func resetDenyText() { denyText = config.deny.joined(separator: "\n") }

    func setOn(_ v: Bool) { v ? turnOn(minutes: duration) : turnOff() }

    // the flag holds the end time in unix seconds, or nothing for "until turned off"
    func turnOn(minutes: Int) {
        try? FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)
        let end = minutes > 0 ? String(Int(Date().timeIntervalSince1970) + minutes * 60) : ""
        try? end.write(toFile: flag, atomically: true, encoding: .utf8)
        reload()
    }

    func turnOff() {
        try? FileManager.default.removeItem(atPath: flag)
        reload()
    }

    // picking a duration while isolation is on restarts the countdown
    func setDuration(_ minutes: Int) {
        duration = minutes
        UserDefaults.standard.set(minutes, forKey: "duration")
        if on { turnOn(minutes: minutes) }
    }

    func setRule(_ key: String, _ v: Bool) {
        var c = Config.load()
        if v { c.enabled.insert(key) } else { c.enabled.remove(key) }
        c.save()
        reload()
    }

    func addExample(_ re: String) {
        var lines = denyText.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if !lines.contains(re) { lines.append(re) }
        denyText = lines.joined(separator: "\n")
    }

    func saveDeny() {
        var c = Config.load()
        c.deny = denyText.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        c.save()
        reload()
        resetDenyText()
    }

    // a LaunchAgent that opens the app at login; launchd picks it up at the next login
    func setAutostart(_ v: Bool) {
        if v {
            let plist: [String: Any] = [
                "Label": "local.safety-ai",
                "ProgramArguments": ["/usr/bin/open", Bundle.main.bundlePath],
                "RunAtLoad": true,
            ]
            try? FileManager.default.createDirectory(atPath: (loginAgent as NSString).deletingLastPathComponent,
                                                     withIntermediateDirectories: true)
            (plist as NSDictionary).write(toFile: loginAgent, atomically: true)
        } else {
            try? FileManager.default.removeItem(atPath: loginAgent)
        }
        autostart = FileManager.default.fileExists(atPath: loginAgent)
    }
}

struct SettingsView: View {
    @ObservedObject var m: Model

    var body: some View {
        TabView(selection: $m.tab) {
            rulesTab.tabItem { Label("Rules", systemImage: "lock.shield") }.tag("rules")
            settingsTab.tabItem { Label("Settings", systemImage: "gearshape") }.tag("settings")
        }
        .padding(.top, 8)
        // Form scrolls and has no height of its own, so the window needs an explicit one
        .frame(minWidth: 480, idealWidth: 500, minHeight: 520, idealHeight: 880)
    }

    var rulesTab: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { m.on }, set: m.setOn)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(m.on ? "Isolation is on" : "Isolation is off", systemImage: m.on ? "lock.fill" : "lock.open")
                            .font(.headline)
                        Text(m.on ? "isolation.on.hint" : "isolation.off.hint")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                VStack(alignment: .leading, spacing: 2) {
                    // a Picker label is clipped to one height, so the hint goes on its own line
                    Picker("Duration", selection: Binding(get: { m.duration }, set: m.setDuration)) {
                        ForEach(durations, id: \.self) { Text(durationTitle($0)).tag($0) }
                    }
                    Text("duration.hint").font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if m.on, let end = m.until {
                    // redraw every 20 s so the countdown moves
                    TimelineView(.periodic(from: .now, by: 20)) { _ in
                        Label(remainingTitle(end), systemImage: "timer").foregroundStyle(.orange)
                    }
                }
                if !m.hookInstalled { hookWarning }
            }
            Section {
                ForEach(rules, id: \.key) { r in
                    Toggle(isOn: rule(r.key)) { described(r.title, r.detail) }
                }
            } header: {
                Text("Block")
            } footer: {
                Text("block.hint").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle(isOn: rule("ask")) { described("Ask for permission", t("ask.hint")) }
            }
            Section {
                Text("custom.hint").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $m.denyText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 90)
                HStack {
                    Menu("Add example") {
                        ForEach(examples, id: \.re) { ex in
                            Button("\(ex.re)   —   \(t(ex.what))") { m.addExample(ex.re) }
                        }
                    }
                    .fixedSize()
                    Spacer()
                    Button("Save", action: m.saveDeny)
                        .disabled(m.denyText == m.config.deny.joined(separator: "\n"))
                        .keyboardShortcut("s")
                }
            } header: {
                Text("Custom rules")
            }
        }
        .formStyle(.grouped)
    }

    var settingsTab: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { m.autostart }, set: m.setAutostart)) { described("Launch at login", t("login.hint")) }
            }
            Section {
                agentRow("Claude Code", m.hookInstalled)
                Text("hook.hint").font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Agents")
            }
            Section {
                LabeledContent("Rules and switch") {
                    Button("Show in Finder") {
                        NSWorkspace.shared.selectFile(conf, inFileViewerRootedAtPath: stateDir)
                    }
                }
                Text(stateDir.replacingOccurrences(of: home, with: "~"))
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                Text("storage.hint").font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Where settings are stored")
            }
            Section {
                Text("language.hint").font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Language")
            }
        }
        .formStyle(.grouped)
    }

    func agentRow(_ name: String, _ ok: Bool) -> some View {
        LabeledContent(name) {
            Label(ok ? "hook connected" : "hook missing, run install.sh",
                  systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .red)
        }
    }

    var hookWarning: some View {
        Label("Hook is not installed, run install.sh", systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
    }

    func rule(_ key: String) -> Binding<Bool> {
        Binding(get: { m.config.enabled.contains(key) }, set: { m.setRule(key, $0) })
    }

    func described(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LocalizedStringKey(title))
            Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    let model = Model()
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let toggle = NSMenuItem(title: t("Isolation mode"), action: #selector(flip), keyEquivalent: "")
    var window: NSWindow?
    var watch: AnyCancellable?

    var ruleItems: [NSMenuItem] = []
    var durationItems: [NSMenuItem] = []
    var askItem, loginItem: NSMenuItem!

    func applicationDidFinishLaunching(_ n: Notification) {
        toggle.target = self
        let onFor = NSMenu()
        for m in durations {
            durationItems.append(add(onFor, durationTitle(m), #selector(turnOnFor), tag: m))
        }
        let onForItem = NSMenuItem(title: t("Turn on for"), action: nil, keyEquivalent: "")
        onForItem.submenu = onFor

        let block = NSMenu()
        for (i, r) in rules.enumerated() {
            ruleItems.append(add(block, r.title, #selector(flipRule), tag: i))
        }
        block.addItem(.separator())
        askItem = add(block, "Ask for permission", #selector(flipAsk))
        add(block, "Custom rules…", #selector(openSettings))
        let blockItem = NSMenuItem(title: t("Block"), action: nil, keyEquivalent: "")
        blockItem.submenu = block

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(toggle)
        menu.addItem(onForItem)
        menu.addItem(blockItem)
        menu.addItem(.separator())
        loginItem = add(menu, "Launch at login", #selector(flipLogin))
        menu.addItem(.separator())
        add(menu, "Settings…", #selector(openSettings), key: ",")
        menu.addItem(NSMenuItem(title: t("Quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        NSApp.mainMenu = mainMenu()

        watch = model.$on.combineLatest(model.$until).sink { [weak self] on, until in self?.showState(on, until) }
        model.reload()
        let args = CommandLine.arguments
        // debug runs (--snapshot, --dump-menu) must never take focus, or the user's typing lands in them
        if args.contains("--snapshot") || args.contains("--dump-menu") {
            NSApp.setActivationPolicy(.prohibited)
        }
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.model.reload() }

        // SafetyAI --dump-menu: prints the lock menu with checkmarks and quits
        if args.contains("--dump-menu") {
            func dump(_ m: NSMenu, _ indent: String) {
                menuWillOpen(m)
                for mi in m.items {
                    print(mi.isSeparatorItem ? indent + "---" : indent + (mi.state == .on ? "[x] " : "[ ] ") + mi.title)
                    if let sub = mi.submenu { dump(sub, indent + "    ") }
                }
            }
            dump(menu, "")
            exit(0)
        }
        // SafetyAI --snapshot out.png [rules|settings]: renders the window to a PNG and quits (for visual checks)
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            if i + 2 < args.count { model.tab = args[i + 2] }
            openSettings()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                if let v = self?.window?.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                    v.cacheDisplay(in: v.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[i + 1]))
                }
                NSApp.terminate(nil)
            }
        }
    }

    // Edit menu, so copy/paste work in the rules editor
    func mainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu()
        appItem.submenu?.addItem(NSMenuItem(title: t("Quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let editItem = NSMenuItem()
        let edit = NSMenu(title: t("Edit"))
        edit.addItem(NSMenuItem(title: t("Undo"), action: Selector(("undo:")), keyEquivalent: "z"))
        edit.addItem(NSMenuItem(title: t("Redo"), action: Selector(("redo:")), keyEquivalent: "Z"))
        edit.addItem(.separator())
        edit.addItem(NSMenuItem(title: t("Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: t("Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: t("Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: t("Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = edit
        main.addItem(appItem)
        main.addItem(editItem)
        return main
    }

    func showState(_ on: Bool, _ until: Date?) {
        let img = NSImage(systemSymbolName: on ? "lock.fill" : "lock.open", accessibilityDescription: nil)
        img?.isTemplate = true
        item.button?.image = img
        let left = on ? until.map(remainingTitle) : nil
        item.button?.toolTip = t(on ? "Claude: commits blocked" : "Claude: commits allowed") + (left.map { " · " + $0 } ?? "")
        toggle.title = t("Isolation mode") + (left.map { " · " + $0 } ?? "")
        toggle.state = on ? .on : .off
    }

    @discardableResult
    func add(_ menu: NSMenu, _ title: String, _ action: Selector, tag: Int = 0, key: String = "") -> NSMenuItem {
        let mi = NSMenuItem(title: t(title), action: action, keyEquivalent: key)
        mi.target = self
        mi.tag = tag
        menu.addItem(mi)
        return mi
    }

    // checkmarks are read fresh every time the menu opens, so they match the settings window and the files
    func menuWillOpen(_ menu: NSMenu) {
        model.reload()
        showState(model.on, model.until)  // refresh the countdown in the title
        for mi in durationItems { mi.state = mi.tag == model.duration ? .on : .off }
        for (i, mi) in ruleItems.enumerated() { mi.state = model.config.enabled.contains(rules[i].key) ? .on : .off }
        askItem.state = model.config.enabled.contains("ask") ? .on : .off
        loginItem.state = model.autostart ? .on : .off
    }

    @objc func flip() { model.setOn(!model.on) }
    // remembers the choice and turns isolation on right away
    @objc func turnOnFor(_ sender: NSMenuItem) {
        model.setDuration(sender.tag)
        model.turnOn(minutes: sender.tag)
    }
    @objc func flipRule(_ sender: NSMenuItem) { let k = rules[sender.tag].key; model.setRule(k, !model.config.enabled.contains(k)) }
    @objc func flipAsk() { model.setRule("ask", !model.config.enabled.contains("ask")) }
    @objc func flipLogin() { model.setAutostart(!model.autostart) }
    @objc func openSettings() {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(m: model)))
            w.title = "Safety AI"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.setContentSize(NSSize(width: 500, height: 880))
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.center()
            window = w
        }
        model.reload()
        model.resetDenyText()
        // --snapshot must not take keyboard focus, or the user's typing lands in the rules editor
        if CommandLine.arguments.contains("--snapshot") { window?.orderFrontRegardless(); return }
        // the app shows in the Dock only while the settings window is open
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    // click on the Dock icon while the window is minimized
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }
}

// SafetyAI --ask <title> <text> <deny> <allow> [seconds]: the hook's Allow/Deny window.
// Prints the pressed button. Deny is the default (Return); when time runs out it prints deny.
func ask(_ a: [String]) -> Never {
    let (title, text, denyTitle, allowTitle) = (a[0], a[1], a[2], a[3])
    var left = a.count > 4 ? Int(a[4]) ?? 90 : 90
    NSApp.setActivationPolicy(.accessory)
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = text
    let deny = alert.addButton(withTitle: denyTitle)
    alert.addButton(withTitle: allowTitle)

    // countdown: shrinking bar and a line under it, so it is clear the window will not wait forever
    let bar = NSProgressIndicator(frame: NSRect(x: 0, y: 22, width: 320, height: 12))
    bar.style = .bar
    bar.isIndeterminate = false
    bar.minValue = 0
    bar.maxValue = Double(left)
    let label = NSTextField(labelWithString: "")
    label.frame = NSRect(x: 0, y: 0, width: 320, height: 16)
    label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
    label.textColor = .secondaryLabelColor
    let box = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 36))
    box.addSubview(bar)
    box.addSubview(label)
    alert.accessoryView = box

    func show() {
        bar.doubleValue = Double(left)
        deny.title = "\(denyTitle) (\(left))"
        label.stringValue = String(format: t("No answer: %@ in %d s"), denyTitle.lowercased(), left)
    }
    show()
    let tick = Timer(timeInterval: 1, repeats: true) { _ in
        left -= 1
        show()
        if left <= 0 { NSApp.stopModal(withCode: .alertFirstButtonReturn) }
    }
    RunLoop.main.add(tick, forMode: .modalPanel)
    if let out = ProcessInfo.processInfo.environment["SAFETY_AI_SNAPSHOT"] {
        // for visual checks: render the window after a moment, then deny
        let snap = Timer(timeInterval: 1.5, repeats: false) { _ in
            if let v = alert.window.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                v.cacheDisplay(in: v.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
            }
            NSApp.stopModal(withCode: .alertFirstButtonReturn)
        }
        RunLoop.main.add(snap, forMode: .modalPanel)
    } else {
        NSApp.activate(ignoringOtherApps: true)
    }
    let r = alert.runModal()
    print(r == .alertSecondButtonReturn ? allowTitle : denyTitle)
    exit(0)
}

let app = NSApplication.shared
if let i = CommandLine.arguments.firstIndex(of: "--ask"), CommandLine.arguments.count >= i + 5 {
    ask(Array(CommandLine.arguments[(i + 1)...]))
}
let delegate = App()
app.delegate = delegate
app.run()
