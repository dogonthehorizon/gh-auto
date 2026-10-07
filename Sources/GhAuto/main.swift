import AppKit

// `gh-auto --once` prints the current PR list and exits; handy for checking auth and the query.
if CommandLine.arguments.contains("--once") {
    do {
        let prs = try await GitHubClient().fetchOpenPullRequests()
        print("\(prs.count) open pull request(s) for: \(GitHubClient.searchQuery)")
        for pr in prs {
            print("\(pr.repository.nameWithOwner)#\(pr.number)\(pr.isDraft ? " [draft]" : "")  \(pr.title)")
        }
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: StatusController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = StatusController()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Menu bar only: no Dock icon, no app switcher entry (LSUIElement in Info.plist does the same for the bundle).
app.setActivationPolicy(.accessory)
app.run()
