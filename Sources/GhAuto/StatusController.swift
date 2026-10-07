import AppKit
import os

/// Owns the menu bar item. Polling is handed to NSBackgroundActivityScheduler so macOS can
/// defer or coalesce it (battery, thermal, Low Power Mode), and is skipped while you're away.
@MainActor
final class StatusController: NSObject, NSMenuDelegate {
    private static let pollInterval: TimeInterval = 120
    private static let awayThreshold: TimeInterval = 10 * 60
    private static let pullsDashboard = URL(string: "https://github.com/pulls")!
    private static let log = Logger(subsystem: "com.dogonthehorizon.gh-auto", category: "poll")

    private let client = GitHubClient()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let scheduler = NSBackgroundActivityScheduler(identifier: "com.dogonthehorizon.gh-auto.poll")
    private var inFlight: Task<Void, Never>?
    private var screenLocked = false

    private var pullRequests: [PullRequest] = []
    private var lastError: Error?
    private var lastUpdated: Date?

    override init() {
        super.init()
        menu.delegate = self
        statusItem.menu = menu
        render()
        startScheduler()

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(refresh), name: NSWorkspace.didWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(refresh), name: NSWorkspace.screensDidWakeNotification, object: nil)

        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(self, selector: #selector(screenDidLock), name: .init("com.apple.screenIsLocked"), object: nil)
        distributed.addObserver(self, selector: #selector(screenDidUnlock), name: .init("com.apple.screenIsUnlocked"), object: nil)

        refresh()
    }

    // MARK: Polling

    private func startScheduler() {
        scheduler.repeats = true
        scheduler.interval = Self.pollInterval
        scheduler.tolerance = Self.pollInterval / 4
        scheduler.qualityOfService = .utility
        scheduler.schedule { [weak self] completion in
            // Called on a background queue; hop to the main actor and report back when done.
            Task { @MainActor in
                await self?.scheduledPoll()
                completion(.finished)
            }
        }
    }

    private func scheduledPoll() async {
        if let reason = awayReason() {
            Self.log.notice("skip poll: \(reason, privacy: .public)")
            return
        }
        await poll(trigger: "scheduled")
    }

    /// Non-nil when nobody is looking at the menu bar, so a background poll would be wasted.
    private func awayReason() -> String? {
        if screenLocked { return "screen locked" }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        if idle >= Self.awayThreshold { return "idle \(Int(idle))s" }
        return nil
    }

    @objc private func screenDidLock() {
        screenLocked = true
    }

    @objc private func screenDidUnlock() {
        screenLocked = false
        refresh()
    }

    @objc private func refresh() {
        Task { await poll(trigger: "manual") }
    }

    private func poll(trigger: String) async {
        if let inFlight { return await inFlight.value }
        let task = Task(priority: .utility) { [client] in
            do {
                let prs = try await client.fetchOpenPullRequests()
                self.pullRequests = prs
                self.lastError = nil
                self.lastUpdated = Date()
                Self.log.notice("poll (\(trigger, privacy: .public)): \(prs.count) PRs")
            } catch {
                self.lastError = error
                Self.log.error("poll (\(trigger, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)")
            }
            self.render()
        }
        inFlight = task
        await task.value
        inFlight = nil
    }

    // MARK: Rendering

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }

    private func render() {
        renderButton()
        renderMenu()
    }

    private func renderButton() {
        guard let button = statusItem.button else { return }
        button.image = lastError == nil ? StatusIcon.pullRequest : StatusIcon.error
        button.imagePosition = .imageLeading
        button.title = lastUpdated == nil ? "" : " \(pullRequests.count)"
    }

    private func renderMenu() {
        menu.removeAllItems()

        if let lastError {
            let item = NSMenuItem(title: lastError.localizedDescription, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            menu.addItem(.separator())
        }

        if pullRequests.isEmpty {
            let title = lastUpdated == nil ? "Loading…" : "No open pull requests"
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            let byRepo = Dictionary(grouping: pullRequests, by: \.repository.nameWithOwner)
            for repo in byRepo.keys.sorted() {
                menu.addItem(.sectionHeader(title: repo))
                for pr in byRepo[repo]! {
                    menu.addItem(menuItem(for: pr))
                }
            }
        }

        menu.addItem(.separator())
        if let lastUpdated {
            let formatted = lastUpdated.formatted(date: .omitted, time: .shortened)
            let item = NSMenuItem(title: "Updated \(formatted)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(actionItem("Refresh", #selector(refresh), key: "r"))
        menu.addItem(actionItem("Open GitHub Pull Requests", #selector(openDashboard), key: "o"))
        menu.addItem(.separator())

        let login = actionItem("Launch at Login", #selector(toggleLaunchAtLogin), key: "")
        login.state = LaunchAtLogin.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(NSMenuItem(title: "Quit gh-auto", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func menuItem(for pr: PullRequest) -> NSMenuItem {
        let prefix = pr.isDraft ? "◌ " : ""
        let title = Self.truncated("\(prefix)#\(pr.number) \(pr.title)", toWidth: Self.maxItemWidth)
        let item = actionItem(title, #selector(openPullRequest(_:)), key: "")
        item.representedObject = pr.url
        item.toolTip = "\(pr.title)\n\(pr.url.absoluteString)"
        return item
    }

    // NSMenu grows to fit its widest item, so long PR titles are clipped before they get there.
    private static let maxItemWidth: CGFloat = 420
    private static let menuFont = NSFont.menuFont(ofSize: 0)

    private static func truncated(_ title: String, toWidth maxWidth: CGFloat) -> String {
        func width(_ s: String) -> CGFloat { (s as NSString).size(withAttributes: [.font: menuFont]).width }
        guard width(title) > maxWidth else { return title }

        // Binary search for the longest prefix that fits alongside the ellipsis.
        let chars = Array(title)
        var low = 0, high = chars.count
        while low < high {
            let mid = (low + high + 1) / 2
            if width(String(chars[..<mid]) + "…") <= maxWidth { low = mid } else { high = mid - 1 }
        }
        return String(chars[..<low]).trimmingCharacters(in: .whitespaces) + "…"
    }

    private func actionItem(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    // MARK: Actions

    @objc private func openPullRequest(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openDashboard() {
        NSWorkspace.shared.open(Self.pullsDashboard)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try LaunchAtLogin.toggle()
        } catch {
            lastError = error
        }
        render()
    }
}
