import Foundation
import os
#if canImport(UIKit)
import UIKit
#endif

/// A short trail of what the app was doing, for working out crashes. Each
/// session writes Library/Logs/Diagnostics/session.log line by line (written
/// straight through, so the lines survive a crash) and ends with "END" when
/// the app goes to the background. A session found at launch without that
/// ending was cut short — it's kept as crash-<date>.log (the last few).
///
/// Read off a connected phone with:
///   xcrun devicectl device copy from --device <udid> --domain-type appDataContainer
///     --domain-identifier com.collagestudio.app --source Library/Logs/Diagnostics
///     --destination <folder>
/// iOS's own crash reports (the stack) are in --domain-type systemCrashLogs.
enum Diagnostics {
    private static let endMark = "END"
    private static let keepCrashLogs = 5
    private static var handle: FileHandle?
    private static let queue = DispatchQueue(label: "CollageStudio.diagnostics")

    static var folder: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Diagnostics", isDirectory: true)
    }
    private static var sessionURL: URL { folder.appendingPathComponent("session.log") }

    /// Keeps the last session if it was cut short, then starts a new one.
    static func start() {
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        if let last = try? String(contentsOf: sessionURL, encoding: .utf8),
           !last.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(endMark) {
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            try? fm.moveItem(at: sessionURL, to: folder.appendingPathComponent("crash-\(stamp).log"))
            prune()
        }
        try? fm.removeItem(at: sessionURL)
        fm.createFile(atPath: sessionURL.path, contents: nil)
        handle = try? FileHandle(forWritingTo: sessionURL)
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        var device = ""
        #if canImport(UIKit)
        device = "\(UIDevice.current.model) iOS \(UIDevice.current.systemVersion)"
        #endif
        log("START v\(version) (\(build)) \(device)")
        watchMainThread()
    }

    /// Notes when the main thread stops answering for over 2 seconds (iOS
    /// ends an app frozen for 10, without a crash of its own), and how long
    /// the freeze lasted once it's over.
    private static func watchMainThread() {
        mainThread = mach_thread_self()
        let lastSeen = OSAllocatedUnfairLock(initialState: Date())
        var samples = 0
        var stuckSince: Date?
        var lastTick = Date()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 0.5)
        timer.setEventHandler {
            let now = Date()
            // A long gap between ticks: the app was suspended, not frozen.
            if now.timeIntervalSince(lastTick) > 1.5 { lastSeen.withLock { $0 = now } }
            lastTick = now
            let seen = lastSeen.withLock { $0 }
            if now.timeIntervalSince(seen) > 2 {
                if stuckSince == nil { stuckSince = seen; samples = 0; write("\(timestamp()) main thread stuck\n") }
                // Where it's stuck: a few looks at its stack, a second apart.
                if samples < 3, now.timeIntervalSince(seen) > 2.5 + Double(samples) {
                    samples += 1
                    write("\(timestamp()) main thread stack \(samples):\n" + takeWrites() + mainThreadStack())
                }
            } else if let since = stuckSince {
                write(String(format: "%@ main thread back after %.1fs\n", timestamp(), seen.timeIntervalSince(since)))
                stuckSince = nil
            } else {
                _ = takeWrites()
            }
            DispatchQueue.main.async { lastSeen.withLock { $0 = Date() } }
        }
        timer.resume()
        mainWatch = timer
    }
    private static var mainWatch: DispatchSourceTimer?

    /// How often each layout-driven value was set since the last look:
    /// during a freeze, the one that keeps changing is the loop.
    private static let writes = OSAllocatedUnfairLock(initialState: [String: Int]())
    static func count(_ name: String) { writes.withLock { $0[name, default: 0] += 1 } }
    private static func takeWrites() -> String {
        let counts = writes.withLock { w -> [String: Int] in defer { w = [:] }; return w }
        let top = counts.sorted { $0.value > $1.value }.prefix(8)
        return top.isEmpty ? "  writes: none\n" : "  writes: " + top.map { "\($0.key)×\($0.value)" }.joined(separator: " ") + "\n"
    }
    private static var mainThread: thread_act_t = 0

    /// The main thread's call stack, one frame a line ("image +offset
    /// symbol"; app frames resolve with atos against the dSYM). Walks the
    /// frame pointers while the thread is paused — no allocation until it
    /// runs again.
    private static func mainThreadStack() -> String {
        #if arch(arm64)
        let maxFrames = 48
        var pcs = [UInt](repeating: 0, count: maxFrames)
        var count = 0
        var state = arm_thread_state64_t()
        var stateCount = mach_msg_type_number_t(MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<UInt32>.size)
        guard thread_suspend(mainThread) == KERN_SUCCESS else { return "  (couldn't pause)\n" }
        let got = withUnsafeMutablePointer(to: &state) {
            $0.withMemoryRebound(to: natural_t.self, capacity: Int(stateCount)) {
                thread_get_state(mainThread, ARM_THREAD_STATE64, $0, &stateCount)
            }
        }
        if got == KERN_SUCCESS {
            pcs.withUnsafeMutableBufferPointer { buf in
                buf[0] = UInt(state.__pc) & 0x0000_000F_FFFF_FFFF
                buf[1] = UInt(state.__lr) & 0x0000_000F_FFFF_FFFF
                count = 2
                var fp = UInt(state.__fp)
                while count < maxFrames, fp != 0, fp & 7 == 0 {
                    // Each frame: [fp] = caller's fp, [fp + 8] = return address.
                    guard let frame = UnsafePointer<UInt>(bitPattern: fp) else { break }
                    let next = frame[0], ret = frame[1] & 0x0000_000F_FFFF_FFFF
                    if ret == 0 { break }
                    buf[count] = ret; count += 1
                    if next <= fp { break }
                    fp = next
                }
            }
        }
        thread_resume(mainThread)
        var out = ""
        for pc in pcs.prefix(count) {
            var info = Dl_info()
            if dladdr(UnsafeRawPointer(bitPattern: pc), &info) != 0, let base = info.dli_fbase {
                let image = info.dli_fname.map { String(cString: $0).split(separator: "/").last.map(String.init) ?? "?" } ?? "?"
                let symbol = info.dli_sname.map { String(cString: $0) } ?? ""
                out += "  \(image) +0x\(String(pc - UInt(bitPattern: base), radix: 16)) \(symbol.prefix(160))\n"
            } else {
                out += "  0x\(String(pc, radix: 16))\n"
            }
        }
        return out
        #else
        return ""
        #endif
    }

    /// One line, with the time.
    static func log(_ message: String) {
        let line = "\(timestamp()) \(message)\n"
        queue.async { write(line) }
    }

    /// On `queue`.
    private static func write(_ line: String) {
        guard let handle, let data = line.data(using: .utf8) else { return }
        handle.seekToEndOfFile()
        handle.write(data)
    }

    /// The app left the screen normally: not a crash if it's never back.
    static func markEnded() { log(endMark) }

    private static func prune() {
        let logs = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("crash-") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in logs.dropFirst(keepCrashLogs) { try? FileManager.default.removeItem(at: old) }
    }

    private static let timeFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
    private static func timestamp() -> String { timeFormat.string(from: Date()) }
}

extension CollageState {
    /// The collage in a line: pages, photos per page, ratio — enough to
    /// rebuild the case that crashed.
    var diagnosticsSummary: String {
        let perPage = pages.map { p in
            let text = p.images.filter(\.isText).count, empty = p.images.filter(\.isPlaceholder).count
            var s = "\(p.images.count)"
            if text > 0 { s += "t\(text)" }
            if empty > 0 { s += "e\(empty)" }
            return s + "c\(p.style.numCols)"
        }
        return "pages \(pages.count) [\(perPage.joined(separator: " "))] on \(currentPageIndex + 1) ratio \(ratio.rawValue)"
    }
}

// Layout reports differing only in a fraction of a point are noise: taking
// them as changes can feed a layout back into itself without end.
extension CGFloat {
    func differs(from other: CGFloat) -> Bool { abs(self - other) > 0.5 }
}
extension CGSize {
    func differs(from other: CGSize) -> Bool { width.differs(from: other.width) || height.differs(from: other.height) }
}
extension CGRect {
    func differs(from other: CGRect) -> Bool {
        minX.differs(from: other.minX) || minY.differs(from: other.minY) || size.differs(from: other.size)
    }
}
