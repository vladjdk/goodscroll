import AppKit
import Combine
import SwiftUI
import GoodScrollCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let settings = AppSettings()
    let tap = ScrollTap()

    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var permissionTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    static let repoURL = URL(string: "https://github.com/vladjdk/goodscroll")!

    // MARK: Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        tap.config = settings.scrollConfig
        settings.scrollConfigPublisher
            .sink { [weak self] config in
                self?.tap.config = config
                self?.refreshIcon()
            }
            .store(in: &cancellables)

        settings.$showMenuBarIcon
            .receive(on: DispatchQueue.main)
            .sink { [weak self] show in self?.setStatusItemVisible(show) }
            .store(in: &cancellables)

        tap.onStateChange = { [weak self] _ in self?.refreshIcon() }

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        ws.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.screensDidWakeNotification, object: nil)

        startTapWhenTrusted(prompt: true)
    }

    /// Launching the app again (e.g. from Finder/Spotlight) opens Settings — the way back in when the icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        tap.stop()
    }

    // MARK: Tap + permission

    private func startTapWhenTrusted(prompt: Bool) {
        if Permissions.isTrusted {
            permissionTimer?.invalidate(); permissionTimer = nil
            tap.start()
        } else {
            if prompt { Permissions.requestIfNeeded() }
            refreshIcon()
            guard permissionTimer == nil else { return }
            // Poll until the user grants Accessibility, then start without requiring a relaunch.
            let t = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
                if Permissions.isTrusted { self?.startTapWhenTrusted(prompt: false) }
            }
            RunLoop.main.add(t, forMode: .common)
            permissionTimer = t
        }
    }

    @objc private func systemDidWake() {
        if tap.state == .running { tap.ensureHealthy() } else { startTapWhenTrusted(prompt: false) }
    }

    // MARK: Status item

    private func setStatusItemVisible(_ visible: Bool) {
        if visible, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            statusItem = item
            refreshIcon()
        } else if !visible, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func refreshIcon() {
        guard let button = statusItem?.button else { return }
        let active = settings.enabled && tap.state == .running
        let needsPermission = !Permissions.isTrusted
        let symbol = needsPermission ? "exclamationmark.triangle" : "computermouse"
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "GoodScroll")
        button.image?.isTemplate = true
        button.appearsDisabled = !active && !needsPermission
        button.toolTip = needsPermission
            ? "GoodScroll needs Device Control & Data Access (Accessibility) permission"
            : (active ? (settings.discrete ? "GoodScroll: \(settings.linesPerNotch) line\(settings.linesPerNotch == 1 ? "" : "s") per notch" : "GoodScroll: on") : "GoodScroll: off")
    }

    // Rebuilt every time it opens so it always reflects current state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !Permissions.isTrusted {
            let warn = NSMenuItem(title: "Permission needed: Device Control & Data Access", action: nil, keyEquivalent: "")
            warn.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
            menu.addItem(warn)
            menu.addItem(item("Open Privacy Settings…", #selector(openAccessibility)))
            menu.addItem(.separator())
        }

        settings.refreshSystemNatural()

        let toggle = item("GoodScroll Enabled", #selector(toggleEnabled), key: "e")
        toggle.state = settings.enabled ? .on : .off
        menu.addItem(toggle)
        menu.addItem(.separator())

        let discrete = item("Discrete Mouse Scrolling", #selector(toggleDiscrete))
        discrete.state = settings.discrete ? .on : .off
        menu.addItem(discrete)

        let presets = [1, 2, 3, 4, 5, 6, 8, 10, 15]
        let linesMenu = NSMenu()
        for n in presets {
            let i = item("\(n)", #selector(setLines(_:)))
            i.tag = n
            i.state = settings.linesPerNotch == n ? .on : .off
            linesMenu.addItem(i)
        }
        if !presets.contains(settings.linesPerNotch) {
            linesMenu.addItem(.separator())
            let custom = NSMenuItem(title: "Custom: \(settings.linesPerNotch)", action: nil, keyEquivalent: "")
            custom.state = .on
            linesMenu.addItem(custom)
        }
        let linesItem = NSMenuItem(title: "Lines per Notch: \(settings.linesPerNotch)", action: nil, keyEquivalent: "")
        linesItem.submenu = linesMenu
        menu.addItem(linesItem)

        let horiz = item("Discrete Horizontal Scrolling", #selector(toggleHorizontal))
        horiz.state = settings.applyHorizontal ? .on : .off
        menu.addItem(horiz)
        menu.addItem(.separator())

        menu.addItem(directionMenu("Mouse Direction", current: settings.mouseDirection, action: #selector(setMouseDirection(_:))))
        menu.addItem(directionMenu("Trackpad Direction", current: settings.trackpadDirection, action: #selector(setTrackpadDirection(_:))))
        menu.addItem(.separator())

        let login = item("Launch at Login", #selector(toggleLogin))
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(showSettings), key: ","))

        let status = NSMenuItem(title: statusLine(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        menu.addItem(.separator())
        menu.addItem(item("About GoodScroll", #selector(openRepo)))
        menu.addItem(item("Quit GoodScroll", #selector(quit), key: "q"))
    }

    private func statusLine() -> String {
        switch tap.state {
        case .running:
            return tap.recoveries == 0 ? "Status: running" : "Status: running (auto-recovered \(tap.recoveries)×)"
        case .stopped: return "Status: stopped"
        case .failed: return "Status: couldn't start event tap"
        }
    }

    private func directionMenu(_ title: String, current: ScrollDirection, action: Selector) -> NSMenuItem {
        let sub = NSMenu()
        for (idx, dir) in ScrollDirection.allCases.enumerated() {
            var label = dir.label
            if dir == .followSystem { label += " (\(settings.systemNatural ? "Natural" : "Traditional"))" }
            let i = item(label, action)
            i.tag = idx
            i.state = dir == current ? .on : .off
            sub.addItem(i)
        }
        let effective = current == .followSystem ? (settings.systemNatural ? "Natural" : "Traditional") : current.label
        let parent = NSMenuItem(title: "\(title): \(effective)", action: nil, keyEquivalent: "")
        parent.submenu = sub
        return parent
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    // MARK: Actions

    @objc private func toggleEnabled() { settings.enabled.toggle() }
    @objc private func setLines(_ sender: NSMenuItem) { settings.linesPerNotch = sender.tag }
    @objc private func toggleDiscrete() { settings.discrete.toggle() }
    @objc private func setMouseDirection(_ sender: NSMenuItem) { settings.mouseDirection = ScrollDirection.allCases[sender.tag] }
    @objc private func setTrackpadDirection(_ sender: NSMenuItem) { settings.trackpadDirection = ScrollDirection.allCases[sender.tag] }
    @objc private func toggleHorizontal() { settings.applyHorizontal.toggle() }
    @objc private func openAccessibility() { Permissions.openAccessibilitySettings() }
    @objc private func openRepo() { NSWorkspace.shared.open(Self.repoURL) }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func toggleLogin() {
        do { try LoginItem.set(!LoginItem.isEnabled) } catch { presentError(error) }
    }

    @objc func showSettings() {
        if settingsWindow == nil {
            let view = SettingsView(settings: settings,
                                    statusProvider: { [weak self] in self?.statusLine() ?? "" },
                                    onRestartTap: { [weak self] in self?.tap.restart() })
            let host = NSHostingController(rootView: view)
            let window = NSWindow(contentViewController: host)
            window.title = "GoodScroll Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert(error: error)
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
