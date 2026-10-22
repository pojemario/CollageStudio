import SwiftUI

@main
struct CollageApp: App {
    @StateObject private var state = CollageState()
    @StateObject private var updates = UpdateChecker()
    /// Shared photos are being read in (each activation asks again).
    @State private var drainingInbox = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // First, so a crash anywhere after it leaves a trail.
        Diagnostics.start()
        #if DEBUG
        UITest.prepare()
        #endif
        CollageTips.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
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
                        Diagnostics.log("ACTIVE \(state.diagnosticsSummary)")
                        updates.checkIfDue()
                        importSharedImages()
                    } else if phase == .background {
                        // Leaving the app: save right away, not after the delay.
                        state.saveProjectNow()
                        Diagnostics.markEnded()
                    }
                }
                .onOpenURL { _ in
                    // The Share Extension opens collagestudio://import after
                    // saving shared photos — import them right away.
                    importSharedImages()
                }
                .sheet(isPresented: $state.showExportOptions) {
                    // Size and format are drop-downs, so it all fits at half height.
                    ExportOptionsView()
                        .environmentObject(state)
                        .presentationDetents([.medium])
                }
                .sheet(isPresented: $state.showPastePageLook) {
                    PastePageLookView(allOtherPages: state.pasteToAllOthers)
                        .environmentObject(state)
                        .presentationDetents([.medium, .large])
                }
                // A newer build is out: offer TestFlight (or the App Store).
                .alert("New Version Available", isPresented: Binding(
                    get: { updates.available != nil },
                    set: { if !$0 { updates.dismiss() } })) {
                    Button("Update") {
                        if let url = updates.updateURL { UIApplication.shared.open(url) }
                        updates.dismiss()
                    }
                    Button("Later", role: .cancel) { updates.later() }
                } message: {
                    let info = updates.available
                    let title = [info?.version, info.map { "(\($0.build))" }].compactMap { $0 }.joined(separator: " ")
                    Text(["das Kolaž \(title) is ready.", info?.notes].compactMap { $0 }.joined(separator: "\n\n"))
                }
                .alert("Add Shared Photos", isPresented: $state.showSharedImportChoice) {
                    Button("Start New Collage") {
                        state.importPendingShared(replacingCurrent: true)
                    }
                    Button("Add to Current Collage") {
                        state.importPendingShared(replacingCurrent: false)
                    }
                    if state.canAddPost {
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
                    Text("Start a new collage with the shared photos, or add them to the one that's open? It stays in Collages either way.")
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
        guard !drainingInbox else { return }
        drainingInbox = true
        let known = Set(state.pendingSharedFiles)
        Task {
            // Decoded and prepared (proxy, thumb) off the main thread.
            let shared = await Task.detached(priority: .userInitiated) {
                SharedInbox.pendingImages(skipping: known).map { ($0.url, $0.image) }
            }.value
            drainingInbox = false
            addShared(shared)
        }
    }

    private func addShared(_ shared: [(URL, CollageImage)]) {
        guard !shared.isEmpty else { return }

        if state.images.isEmpty {
            // Empty collage — no conflict, import straight away (a new
            // collage: Images panel up).
            state.addPreparedImages(shared.map(\.1))
            SharedInbox.remove(shared.map(\.0))
            state.openImagesPanel()
        } else {
            // Images already present: let the user decide whether to start
            // a fresh collage or append the shared photos to it. The inbox
            // files stay until then.
            state.pendingSharedImages.append(contentsOf: shared.map(\.1))
            state.pendingSharedFiles.append(contentsOf: shared.map(\.0))
            state.showSharedImportChoice = true
        }
    }
}
