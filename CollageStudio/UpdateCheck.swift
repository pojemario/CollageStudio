import SwiftUI
import StoreKit

/// The newest build, as published in a public gist (updated with each
/// TestFlight release, once the build is available to testers).
struct UpdateInfo: Decodable, Equatable {
    var version: String?
    var build: Int
    var notes: String?
    /// Opens TestFlight (its app, or the public link).
    var testflightURL: String?
    /// For App Store installs, when the app is listed.
    var appStoreURL: String?
}

/// Tells the user when a newer build is out and offers to open TestFlight
/// (or the App Store) to get it. TestFlight has no public "latest build"
/// lookup, so TestFlight installs read the gist; App Store installs ask the
/// App Store itself. Builds run from Xcode don't check (unless launched
/// with `-updateCheck`). Checked when the app becomes active, at most every
/// few hours; "Later" stays quiet until a still newer build comes out.
@MainActor
final class UpdateChecker: ObservableObject {
    @Published private(set) var available: UpdateInfo?
    /// Where `available` should send the user.
    private(set) var updateURL: URL?

    static let feed = URL(string: "https://gist.githubusercontent.com/pojemario/ee99aac07e9a69663fae653ad672e3c2/raw/daskolaz-version.json")!
    private static let skippedKey = "updateSkippedBuild"
    private var lastCheck: Date = .distantPast

    private var currentBuild: Int {
        #if DEBUG
        // `-pretendBuild N`: act as an older build, to see the prompt.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-pretendBuild"), i + 1 < args.count, let n = Int(args[i + 1]) { return n }
        #endif
        return Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0
    }
    private var currentVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    func checkIfDue() {
        guard Date().timeIntervalSince(lastCheck) > 4 * 3600 else { return }
        lastCheck = Date()
        Task { await check() }
    }

    func later() {
        if let build = available?.build { UserDefaults.standard.set(build, forKey: Self.skippedKey) }
        available = nil
    }

    func dismiss() { available = nil }

    private enum Source { case testFlight, appStore, xcode }

    private func source() async -> Source {
        #if DEBUG
        return .xcode
        #else
        guard case .verified(let t)? = try? await AppTransaction.shared else { return .xcode }
        switch t.environment {
        case .production: return .appStore
        case .sandbox: return .testFlight
        default: return .xcode
        }
        #endif
    }

    private func check() async {
        switch await source() {
        case .appStore:
            await checkAppStore()
        case .testFlight:
            await checkFeed()
        case .xcode:
            guard ProcessInfo.processInfo.arguments.contains("-updateCheck") else { return }
            await checkFeed()
        }
    }

    private func checkFeed() async {
        var request = URLRequest(url: Self.feed, cachePolicy: .reloadIgnoringLocalCacheData)
        request.timeoutInterval = 10
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let info = try? JSONDecoder().decode(UpdateInfo.self, from: data),
              info.build > currentBuild,
              info.build != UserDefaults.standard.integer(forKey: Self.skippedKey) else { return }
        Diagnostics.log("update available: build \(info.build) (running \(currentBuild))")
        updateURL = Self.trustedTestFlightURL(info.testflightURL)
        var shown = info
        shown.notes = info.notes.map { String($0.prefix(300)) }
        available = shown
    }

    /// App Store installs: the App Store's own listing decides.
    private func checkAppStore() async {
        guard let id = Bundle.main.bundleIdentifier,
              let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(id)"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = (json["results"] as? [[String: Any]])?.first,
              let version = result["version"] as? String,
              Self.isNewer(version, than: currentVersion) else { return }
        // "Later" for an App Store version is remembered by its number.
        let marker = Self.versionMarker(version)
        guard marker != UserDefaults.standard.integer(forKey: Self.skippedKey) else { return }
        // Only an App Store link.
        updateURL = (result["trackViewUrl"] as? String).flatMap(URL.init(string:))
            .flatMap { $0.scheme == "https" && $0.host == "apps.apple.com" ? $0 : nil }
        available = UpdateInfo(version: version, build: marker, notes: result["releaseNotes"] as? String,
                               testflightURL: nil, appStoreURL: updateURL?.absoluteString)
    }

    /// The feed is only a gist: the link it gives is opened only if it
    /// goes to TestFlight; anything else falls back to the TestFlight app.
    static func trustedTestFlightURL(_ string: String?) -> URL {
        let fallback = URL(string: "itms-beta://")!
        guard let string, let url = URL(string: string) else { return fallback }
        if url.scheme == "itms-beta" { return url }
        if url.scheme == "https", url.host == "testflight.apple.com" { return url }
        return fallback
    }

    /// "2.10" is newer than "2.9".
    static func isNewer(_ a: String, than b: String) -> Bool {
        a.compare(b, options: .numeric) == .orderedDescending
    }

    /// A version as one number (2.3.1 → 2_003_001), for remembering "Later".
    private static func versionMarker(_ v: String) -> Int {
        let parts = v.split(separator: ".").compactMap { Int($0) } + [0, 0, 0]
        return parts[0] * 1_000_000 + parts[1] * 1_000 + parts[2]
    }
}
