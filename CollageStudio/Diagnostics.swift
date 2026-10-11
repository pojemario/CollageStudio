import Foundation
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
    }

    /// One line, with the time.
    static func log(_ message: String) {
        let line = "\(timestamp()) \(message)\n"
        queue.async {
            guard let handle, let data = line.data(using: .utf8) else { return }
            handle.seekToEndOfFile()
            handle.write(data)
        }
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
