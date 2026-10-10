import SwiftUI

@main
struct CollageApp: App {
    @StateObject private var state = CollageState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                // The backdrop and glass chrome are designed light; keep the
                // system from flipping the text white in dark mode.
                .environmentObject(state)
                // Cap Dynamic Type scaling so the compact editor controls keep
                // their designed proportions regardless of the device's system
                // text size setting.
                .dynamicTypeSize(...DynamicTypeSize.large)
                .overlay {
                    if state.savePhase != .idle {
                        // The overlay sits outside ContentView's
                        // .environmentObject scope, so inject the state
                        // explicitly or SavingOverlay crashes on first access.
                        SavingOverlay()
                            .environmentObject(state)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: state.savePhase)
                .onChange(of: scenePhase) { _, phase in
                    // Pick up images shared into the app via the Share Extension
                    // (e.g. from Photos) whenever the app becomes active.
                    if phase == .active {
                        importSharedImages()
                    } else if phase == .background {
                        // Leaving the app: save right away, not after the delay.
                        state.saveProjectNow()
                    }
                }
                .onOpenURL { _ in
                    // The Share Extension opens collagestudio://import after
                    // saving shared photos — import them right away.
                    importSharedImages()
                }
                .sheet(isPresented: $state.showExportOptions) {
                    ExportOptionsView()
                        .environmentObject(state)
                        .presentationDetents([.medium, .large])
                }
                .alert("Add Shared Photos", isPresented: $state.showSharedImportChoice) {
                    Button("Start New Collage", role: .destructive) {
                        state.importPendingShared(replacingCurrent: true)
                    }
                    Button("Add to Current Collage") {
                        state.importPendingShared(replacingCurrent: false)
                    }
                    if state.pages.count < CollageState.maxPages {
                        Button("Add as New Page") {
                            state.importPendingSharedAsNewPage()
                        }
                    }
                    if state.pages.count > 1 || state.pendingSharedImages.count > 4 {
                        Button("Burst Across Pages") {
                            state.importPendingSharedBurst()
                        }
                    }
                    Button("Cancel", role: .cancel) {
                        state.discardPendingShared()
                    }
                } message: {
                    Text("Your collage already contains \(state.images.count) photo\(state.images.count == 1 ? "" : "s"). Start a new collage with the shared photos, or add them to the current one?")
                }
        }
        #if os(macOS)
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
        #endif
    }

    private func importSharedImages() {
        // The last collage is still loading: come back once it's in place,
        // so shared photos join it instead of being overwritten by it.
        guard !state.isRestoringProject else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { importSharedImages() }
            return
        }
        let shared = SharedInbox.drainPendingImages()
        guard !shared.isEmpty else { return }

        if state.images.isEmpty {
            // Empty collage — no conflict, import straight away.
            state.addImages(shared)
        } else {
            // Images already present: let the user decide whether to start
            // a fresh collage or append the shared photos to it.
            state.pendingSharedImages.append(contentsOf: shared)
            state.showSharedImportChoice = true
        }
    }
}

/// Version shown next to the logo, e.g. "v1.0" over "142 · ab12cd3". The build
/// number is the git commit count and GitCommit the short hash ("+" when
/// built with uncommitted changes) — both stamped into Info.plist at build
/// time by the "Stamp Build Version" phase — so any installed build can be
/// traced to its commit and features.
enum AppVersion {
    /// "v1.0".
    static var version: String {
        "v" + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
    }

    /// "142 · ab12cd3".
    static var build: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let number = info["CFBundleVersion"] as? String ?? "?"
        return (info["GitCommit"] as? String).map { "\(number) · \($0)" } ?? number
    }

    static var label: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        if let commit = info["GitCommit"] as? String {
            return "v\(version) (\(build) · \(commit))"
        }
        return "v\(version) (\(build))"
    }
}

/// The version next to the logo: two small, faint lines.
struct VersionLabel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(AppVersion.version)
            Text(AppVersion.build)
        }
        .font(.system(size: 8, weight: .regular, design: .monospaced))
        .foregroundColor(.secondary.opacity(0.6))
    }
}
