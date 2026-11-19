// English Slack launcher.
//
// Starts a dedicated copy of the Slack desktop app (own profile folder) with
// --remote-debugging-pipe, so the DevTools protocol runs over an anonymous pipe
// that only this process holds: no TCP port, nothing other programs can reach.
// Over that pipe it injects guard.bundle.js (detect.js + guard.js) into every
// Slack window; the guard only switches on for slack.com pages. It also handles
// slack:// links by handing them to that copy.
//
// It never opens a network connection, never reads or sends messages itself, and
// needs no macOS permissions (no Accessibility, Input Monitoring or Automation).

import AppKit
import Darwin

let slackBinary = "/Applications/Slack.app/Contents/MacOS/Slack"
let profileDir = NSHomeDirectory() + "/Library/Application Support/EnglishSlack"

func log(_ message: String) { NSLog("[EnglishSlack] %@", message) }

// MARK: - Spawning Slack

/// Spawns Slack with the given arguments. If `pipe` is given, the child's fd 3
/// reads `pipe.read` and fd 4 writes `pipe.write` (Chromium's remote-debugging-pipe
/// convention). Every other descriptor of ours is closed in the child.
@discardableResult
func spawnSlack(_ args: [String], pipe: (read: Int32, write: Int32)? = nil) -> Bool {
    var actions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&actions)
    defer { posix_spawn_file_actions_destroy(&actions) }
    posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
    posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0)
    posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)
    if let p = pipe {
        posix_spawn_file_actions_adddup2(&actions, p.read, 3)
        posix_spawn_file_actions_adddup2(&actions, p.write, 4)
    }

    var attr: posix_spawnattr_t?
    posix_spawnattr_init(&attr)
    defer { posix_spawnattr_destroy(&attr) }
    // Only descriptors named in the file actions above survive into Slack.
    posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT))

    let argv: [UnsafeMutablePointer<CChar>?] = ([slackBinary] + args).map { strdup($0) } + [nil]
    defer { argv.forEach { free($0) } }

    var pid: pid_t = 0
    let rc = posix_spawn(&pid, slackBinary, &actions, &attr, argv, environ)
    if rc != 0 { log("posix_spawn failed: \(String(cString: strerror(rc)))") }
    return rc == 0
}

/// Creates a pipe whose descriptors are above 4, so dup2 onto 3/4 never collides.
func makePipe() -> (read: Int32, write: Int32) {
    var fds: [Int32] = [0, 0]
    precondition(pipe(&fds) == 0, "pipe() failed")
    let r = fcntl(fds[0], F_DUPFD_CLOEXEC, 10)
    let w = fcntl(fds[1], F_DUPFD_CLOEXEC, 10)
    close(fds[0]); close(fds[1])
    return (r, w)
}

// MARK: - DevTools protocol over the pipe (null-terminated JSON messages)

final class CDP {
    private let readFD: Int32
    private let writeFD: Int32
    private var nextId = 1
    var onEvent: ((_ method: String, _ params: [String: Any], _ sessionId: String?) -> Void)?
    var onClose: (() -> Void)?

    init(readFD: Int32, writeFD: Int32) {
        self.readFD = readFD
        self.writeFD = writeFD
    }

    func start() {
        let fd = readFD
        Thread {
            var buffer = Data()
            var chunk = [UInt8](repeating: 0, count: 1 << 16)
            while case let n = read(fd, &chunk, chunk.count), n > 0 {
                buffer.append(contentsOf: chunk[0..<n])
                while let zero = buffer.firstIndex(of: 0) {
                    let message = buffer[buffer.startIndex..<zero]
                    buffer.removeSubrange(buffer.startIndex...zero)
                    guard let obj = try? JSONSerialization.jsonObject(with: message) as? [String: Any],
                          let method = obj["method"] as? String else { continue } // replies are ignored
                    let params = obj["params"] as? [String: Any] ?? [:]
                    let session = obj["sessionId"] as? String
                    DispatchQueue.main.async { self.onEvent?(method, params, session) }
                }
            }
            DispatchQueue.main.async { self.onClose?() }
        }.start()
    }

    func send(_ method: String, _ params: [String: Any] = [:], session: String? = nil) {
        var msg: [String: Any] = ["id": nextId, "method": method, "params": params]
        nextId += 1
        if let session { msg["sessionId"] = session }
        guard var data = try? JSONSerialization.data(withJSONObject: msg) else { return }
        data.append(0)
        data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = write(writeFD, raw.baseAddress! + offset, raw.count - offset)
                if n <= 0 { break }
                offset += n
            }
        }
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    var cdp: CDP?
    var pendingURLs: [String] = []
    var guardInjected = false
    lazy var guardSource: String = {
        guard let url = Bundle.main.url(forResource: "guard.bundle", withExtension: "js"),
              let src = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("guard.bundle.js missing from the app bundle")
        }
        return src
    }()

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleURL(_:withReply:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = guardSource // fail fast if the bundle is broken
        claimSlackLinks()
        launchSlack()
    }

    /// Starts the dedicated Slack copy over a private pipe.
    func launchSlack() {
        try? FileManager.default.createDirectory(atPath: profileDir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        let toSlack = makePipe()    // we write, Slack reads (its fd 3)
        let fromSlack = makePipe()  // Slack writes (its fd 4), we read
        guard spawnSlack(["--remote-debugging-pipe", "--user-data-dir=" + profileDir],
                         pipe: (toSlack.read, fromSlack.write)) else {
            alert("Could not start Slack.", "Is Slack installed in /Applications?")
            return NSApp.terminate(nil)
        }
        close(toSlack.read)
        close(fromSlack.write)

        let cdp = CDP(readFD: fromSlack.read, writeFD: toSlack.write)
        cdp.onEvent = { [weak self] in self?.handleEvent($0, $1, $2) }
        // Slack quitting closes the pipe. If that happens before the guard was ever
        // injected, our copy handed off to an English Slack that is already open
        // without the guard (Slack allows one process per profile folder).
        cdp.onClose = { [weak self] in
            if self?.guardInjected == false {
                self?.alert("English Slack is already open without the guard.",
                            "Quit it (Slack → Quit Slack) and open English Slack again.")
            }
            NSApp.terminate(nil)
        }
        cdp.start()
        self.cdp = cdp
        // Attach to every window as it is created, paused before it loads anything,
        // so the guard is registered before Slack's page can start. No race.
        cdp.send("Target.setAutoAttach", ["autoAttach": true, "waitForDebuggerOnStart": true, "flatten": true])
    }

    func handleEvent(_ method: String, _ params: [String: Any], _ session: String?) {
        guard method == "Target.attachedToTarget",
              let sid = params["sessionId"] as? String,
              let info = params["targetInfo"] as? [String: Any] else { return }
        if info["type"] as? String == "page" {
            // Every future page load in this window, then the page as it is now.
            // guard.js itself does nothing outside slack.com.
            // Page.enable is required: without it Slack ignores the script on new pages.
            cdp?.send("Page.enable", session: sid)
            cdp?.send("Page.addScriptToEvaluateOnNewDocument", ["source": guardSource], session: sid)
            cdp?.send("Runtime.evaluate", ["expression": guardSource], session: sid)
            log("guard injected")
            guardInjected = true
            flushURLs()
        }
        // Let the window (or worker) continue loading.
        cdp?.send("Runtime.runIfWaitingForDebugger", session: sid)
    }

    // MARK: slack:// links

    @objc func handleURL(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let url = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              url.lowercased().hasPrefix("slack:") else { return }
        pendingURLs.append(url)
        if guardInjected { flushURLs() }
    }

    /// Hands links to the running copy: starting Slack again with the same profile
    /// makes the new process pass its arguments to the running one and exit.
    func flushURLs() {
        for url in pendingURLs { spawnSlack(["--user-data-dir=" + profileDir, url]) }
        pendingURLs.removeAll()
    }

    func claimSlackLinks() {
        let me = Bundle.main.bundleURL
        if NSWorkspace.shared.urlForApplication(toOpen: URL(string: "slack://open")!)?.standardizedFileURL
            == me.standardizedFileURL { return }
        NSWorkspace.shared.setDefaultApplication(at: me, toOpenURLsWithScheme: "slack") { error in
            if let error { log("could not claim slack:// links: \(error.localizedDescription)") }
        }
    }

    func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
