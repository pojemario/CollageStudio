import SwiftUI
import StoreKit

/// Press and hold the logo: what this copy of the app is (version, build,
/// commit, when it was built and installed, where from), the device, how
/// much memory and storage it's using, and the open collage. "Copy" puts
/// it all on the clipboard, for a bug report.
struct AboutView: View {
    @EnvironmentObject var state: CollageState
    @Environment(\.dismiss) private var dismiss
    @State private var source = "…"
    @State private var firstInstalled: Date?
    @State private var storage: StorageInfo?
    @State private var copied = false

    private struct StorageInfo {
        var collagesBytes: Int64
        var logsBytes: Int64
        var cachesBytes: Int64
        var freeBytes: Int64?
    }

    var body: some View {
        NavigationStack {
            // Memory and the like change while it's open.
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Form {
                    ForEach(sections, id: \.title) { section in
                        Section(section.title) {
                            ForEach(section.rows, id: \.0) { row in
                                LabeledContent(row.0) {
                                    Text(row.1)
                                        .monospacedDigit()
                                        .multilineTextAlignment(.trailing)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("About das Kolaž")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(copied ? "Copied" : "Copy") {
                        UIPasteboard.general.string = report
                        copied = true
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .task { await load() }
    }

    // MARK: - Content

    private struct InfoSection {
        let title: String
        let rows: [(String, String)]
    }

    private var sections: [InfoSection] {
        let info = Bundle.main.infoDictionary ?? [:]
        let device = UIDevice.current
        let screen = UIScreen.main
        let process = ProcessInfo.processInfo
        var app: [(String, String)] = [
            ("Version", info["CFBundleShortVersionString"] as? String ?? "?"),
            ("Build", info["CFBundleVersion"] as? String ?? "?"),
            ("Commit", info["GitCommit"] as? String ?? "?"),
            ("Committed", Self.date(info["GitCommitTime"])),
            ("Built", Self.date(info["BuildTime"])),
            ("Installed from", source),
        ]
        if let installed = Self.bundleDate { app.append(("This build installed", Self.format(installed))) }
        if let firstInstalled { app.append(("First installed", Self.format(firstInstalled))) }
        #if DEBUG
        app.append(("Configuration", "Debug"))
        #else
        app.append(("Configuration", "Release"))
        #endif

        let running = Date().timeIntervalSince(Diagnostics.launched)
        let footprint = Int64(Diagnostics.memoryFootprint())
        let available = Int64(os_proc_available_memory())
        var memory: [(String, String)] = [
            ("App is using", Self.bytes(footprint)),
            ("Still available to it", available > 0 ? Self.bytes(available) : "–"),
            ("Device memory", Self.bytes(Int64(process.physicalMemory))),
            ("Running for", Self.duration(running)),
        ]
        memory.append(("Thermal state", Self.thermal(process.thermalState)))
        memory.append(("Low Power Mode", process.isLowPowerModeEnabled ? "On" : "Off"))

        let devices: [(String, String)] = [
            ("Model", Self.modelIdentifier),
            ("System", "\(device.systemName) \(device.systemVersion)"),
            ("Screen", "\(Int(screen.bounds.width)) × \(Int(screen.bounds.height)) pt @\(Int(screen.scale))×"),
            ("Language", Locale.preferredLanguages.first ?? Locale.current.identifier),
            ("Region", Locale.current.region?.identifier ?? "–"),
            ("Time zone", TimeZone.current.identifier),
        ]

        var store: [(String, String)] = [("Saved collages", "\(state.projectStore.summaries.count)")]
        if let storage {
            store.append(("Collages take", Self.bytes(storage.collagesBytes)))
            store.append(("Diagnostics logs", Self.bytes(storage.logsBytes)))
            store.append(("Caches", Self.bytes(storage.cachesBytes)))
            if let free = storage.freeBytes { store.append(("Free on device", Self.bytes(free))) }
        } else {
            store.append(("Collages take", "…"))
        }

        var sections = [
            InfoSection(title: "App", rows: app),
            InfoSection(title: "Memory", rows: memory),
            InfoSection(title: "Device", rows: devices),
            InfoSection(title: "Storage", rows: store),
        ]
        if state.hasAnyImages {
            let photos = state.pages.reduce(0) { $0 + $1.images.filter { !$0.isPlaceholder && !$0.isText }.count }
            let texts = state.pages.reduce(0) { $0 + $1.images.filter(\.isText).count }
            let size = state.pictureSize
            sections.append(InfoSection(title: "Open Collage", rows: [
                ("Pages", "\(state.pages.count)"),
                ("Posts", "\(state.pictureCount)"),
                ("Photos", "\(photos)"),
                ("Text boxes", "\(texts)"),
                ("Ratio", state.ratio.rawValue),
                ("Canvas", "\(Int(size.width)) × \(Int(size.height))"),
                ("Filter", state.colorFilter.title),
            ]))
        }
        return sections
    }

    /// Everything above as plain text.
    private var report: String {
        sections.map { section in
            ([section.title.uppercased()] + section.rows.map { "\($0.0): \($0.1)" }).joined(separator: "\n")
        }
        .joined(separator: "\n\n")
    }

    // MARK: - Loading

    private func load() async {
        if let result = try? await AppTransaction.shared, case .verified(let t) = result {
            firstInstalled = t.originalPurchaseDate
            switch t.environment {
            case .production: source = "App Store"
            case .sandbox: source = "TestFlight"
            default: source = "Xcode"
            }
        } else {
            source = "Xcode"
        }
        storage = await Task.detached(priority: .utility) { Self.measureStorage() }.value
    }

    nonisolated private static func measureStorage() -> StorageInfo {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let free = (try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
        return StorageInfo(collagesBytes: folderSize(ProjectStore.root),
                           logsBytes: folderSize(Diagnostics.folder), cachesBytes: folderSize(caches),
                           freeBytes: free)
    }

    nonisolated private static func folderSize(_ url: URL) -> Int64 {
        guard let walk = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in walk {
            total += Int64((try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    // MARK: - Formatting

    /// When this build was put on the device (the app bundle's date).
    private static var bundleDate: Date? {
        (try? Bundle.main.bundleURL.resourceValues(forKeys: [.creationDateKey]))?.creationDate
    }

    /// "iPhone16,2".
    private static var modelIdentifier: String {
        #if targetEnvironment(simulator)
        let id = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "?"
        return "\(id) (Simulator)"
        #else
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        #endif
    }

    private static func date(_ value: Any?) -> String {
        guard let s = value as? String, let t = TimeInterval(s), t > 0 else { return "–" }
        return format(Date(timeIntervalSince1970: t))
    }

    private static func format(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .memory)
    }

    private static func duration(_ t: TimeInterval) -> String {
        let f = DateComponentsFormatter()
        f.allowedUnits = t < 3600 ? [.minute, .second] : [.hour, .minute]
        f.unitsStyle = .abbreviated
        return f.string(from: t) ?? "–"
    }

    private static func thermal(_ s: ProcessInfo.ThermalState) -> String {
        switch s {
        case .nominal: return "Normal"
        case .fair: return "Warm"
        case .serious: return "Hot"
        case .critical: return "Critical"
        @unknown default: return "–"
        }
    }
}
