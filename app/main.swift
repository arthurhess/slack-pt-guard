// English Slack launcher.
//
// Starts a dedicated copy of the Slack desktop app (own profile folder) with
// --remote-debugging-pipe, so the DevTools protocol runs over an anonymous pipe
// that only this process holds: no TCP port, nothing other programs can reach.
// Over that pipe it injects guard.bundle.js (detect.js + guard.js) into every
// Slack page. It also handles slack:// links by handing them to that copy.
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
func spawnSlack(_ args: [String], pipe: (read: Int32, write: Int32)? = nil) -> pid_t? {
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
    if rc != 0 {
        log("posix_spawn failed: \(String(cString: strerror(rc)))")
        return nil
    }
    return pid
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

/// True if a Slack process is already using our profile folder (e.g. started by
/// hand, without the guard). Reads process arguments via sysctl, no subprocess.
func englishSlackAlreadyRunning() -> Bool {
    var size = 0
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
    guard sysctl(&mib, 4, nil, &size, nil, 0) == 0 else { return false }
    let count = size / MemoryLayout<kinfo_proc>.stride
    var procs = [kinfo_proc](repeating: kinfo_proc(), count: count)
    guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return false }
    let needle = "--user-data-dir=" + profileDir
    for p in procs.prefix(size / MemoryLayout<kinfo_proc>.stride) {
        let pid = p.kp_proc.p_pid
        var argmax: Int32 = 0
        var argmaxSize = MemoryLayout<Int32>.size
        var argMib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        sysctl(&argMib, 2, &argmax, &argmaxSize, nil, 0)
        var buf = [CChar](repeating: 0, count: Int(argmax))
        var bufSize = Int(argmax)
        var procMib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        guard sysctl(&procMib, 3, &buf, &bufSize, nil, 0) == 0 else { continue }
        let bytes = buf.prefix(bufSize).map { UInt8(bitPattern: $0) }
        let text = String(decoding: bytes.map { $0 == 0 ? 0x0A : $0 }, as: UTF8.self)
        if text.contains(slackBinary) && text.contains(needle) { return true }
    }
    return false
}

// MARK: - DevTools protocol over the pipe

final class CDP {
    private let readFD: Int32
    private let writeFD: Int32
    private var nextId = 1
    private var callbacks: [Int: ([String: Any]) -> Void] = [:]
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
            while true {
                let n = read(fd, &chunk, chunk.count)
                if n <= 0 { break }
                buffer.append(contentsOf: chunk[0..<n])
                while let zero = buffer.firstIndex(of: 0) {
                    let message = buffer[buffer.startIndex..<zero]
                    buffer.removeSubrange(buffer.startIndex...zero)
                    if let obj = try? JSONSerialization.jsonObject(with: message) as? [String: Any] {
                        DispatchQueue.main.async { self.dispatch(obj) }
                    }
                }
            }
            DispatchQueue.main.async { self.onClose?() }
        }.start()
    }

    private func dispatch(_ msg: [String: Any]) {
        if let id = msg["id"] as? Int, let cb = callbacks.removeValue(forKey: id) {
            cb(msg)
        } else if let method = msg["method"] as? String {
            onEvent?(method, msg["params"] as? [String: Any] ?? [:], msg["sessionId"] as? String)
        }
    }

    func send(_ method: String, _ params: [String: Any] = [:], session: String? = nil,
              then: (([String: Any]) -> Void)? = nil) {
        let id = nextId
        nextId += 1
        var msg: [String: Any] = ["id": id, "method": method, "params": params]
        if let session { msg["sessionId"] = session }
        if let then { callbacks[id] = then }
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
    var slackPid: pid_t = 0
    var exitSource: DispatchSourceProcess?
    var attachedTargets = Set<String>()
    var pendingURLs: [String] = []
    var ready = false
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
        if englishSlackAlreadyRunning() {
            alert("English Slack is already running without the guard.",
                  "Quit that Slack window (Slack → Quit) and open English Slack again.")
            NSApp.terminate(nil)
            return
        }
        launchSlack()
    }

    // Starts the dedicated Slack copy over a private pipe.
    func launchSlack() {
        try? FileManager.default.createDirectory(atPath: profileDir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        let toSlack = makePipe()    // we write, Slack reads (its fd 3)
        let fromSlack = makePipe()  // Slack writes (its fd 4), we read
        guard let pid = spawnSlack(["--remote-debugging-pipe", "--user-data-dir=" + profileDir],
                                   pipe: (toSlack.read, fromSlack.write)) else {
            alert("Could not start Slack.", "Is Slack installed in /Applications?")
            NSApp.terminate(nil)
            return
        }
        close(toSlack.read)
        close(fromSlack.write)
        slackPid = pid
        log("started Slack pid \(pid)")

        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        source.setEventHandler { [weak self] in
            var status: Int32 = 0
            waitpid(self?.slackPid ?? 0, &status, WNOHANG)
            log("Slack exited")
            NSApp.terminate(nil)
        }
        source.resume()
        exitSource = source

        let cdp = CDP(readFD: fromSlack.read, writeFD: toSlack.write)
        cdp.onEvent = { [weak self] in self?.handleEvent($0, $1, $2) }
        cdp.onClose = { log("pipe closed"); NSApp.terminate(nil) }
        cdp.start()
        self.cdp = cdp
        cdp.send("Target.setDiscoverTargets", ["discover": true])
    }

    func handleEvent(_ method: String, _ params: [String: Any], _ session: String?) {
        switch method {
        case "Target.targetCreated", "Target.targetInfoChanged":
            guard let info = params["targetInfo"] as? [String: Any],
                  info["type"] as? String == "page",
                  let id = info["targetId"] as? String,
                  let urlString = info["url"] as? String,
                  let host = URL(string: urlString)?.host,
                  host == "slack.com" || host.hasSuffix(".slack.com"),
                  !attachedTargets.contains(id) else { return }
            attachedTargets.insert(id)
            cdp?.send("Target.attachToTarget", ["targetId": id, "flatten": true])
        case "Target.attachedToTarget":
            guard let sid = params["sessionId"] as? String else { return }
            // Future page loads in this tab, then the page as it is now.
            cdp?.send("Page.addScriptToEvaluateOnNewDocument", ["source": guardSource], session: sid)
            cdp?.send("Runtime.evaluate", ["expression": guardSource], session: sid)
            log("guard injected")
            if !ready {
                ready = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.flushURLs() }
            }
        case "Target.targetDestroyed":
            if let id = params["targetId"] as? String { attachedTargets.remove(id) }
        case "Target.detachedFromTarget":
            if let id = params["targetId"] as? String { attachedTargets.remove(id) }
        default:
            break
        }
    }

    // MARK: slack:// links

    @objc func handleURL(_ event: NSAppleEventDescriptor, withReply reply: NSAppleEventDescriptor) {
        guard let url = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              url.lowercased().hasPrefix("slack:") else { return }
        pendingURLs.append(url)
        if ready { flushURLs() }
    }

    /// Hands links to the running copy: starting Slack again with the same profile
    /// makes the new process pass its arguments to the running one and exit.
    func flushURLs() {
        let urls = pendingURLs
        pendingURLs.removeAll()
        for url in urls {
            _ = spawnSlack(["--user-data-dir=" + profileDir, url])
        }
    }

    func claimSlackLinks() {
        let me = Bundle.main.bundleURL
        if let current = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "slack://open")!),
           current.standardizedFileURL == me.standardizedFileURL { return }
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
