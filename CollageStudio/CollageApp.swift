import SwiftUI

@main
struct CollageApp: App {
    @StateObject private var state = CollageState()
    @Environment(\.scenePhase) private var scenePhase

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
                        importSharedImages()
                    }
                }
                .onOpenURL { _ in
                    // The Share Extension opens collagestudio://import after
                    // saving shared photos — import them right away.
                    importSharedImages()
                }
                .confirmationDialog("Export", isPresented: $state.showExportOptions) {
                    Button("Current Page") {
                        Task { await state.exportPages(allPages: false) }
                    }
                    Button("All Pages (\(state.pages.count))") {
                        Task { await state.exportPages(allPages: true) }
                    }
                    Button("Cancel", role: .cancel) {}
                }
                .alert("Add Shared Photos", isPresented: $state.showSharedImportChoice) {
                    Button("Start New Collage", role: .destructive) {
                        state.importPendingShared(replacingCurrent: true)
                    }
                    Button("Add to Current Collage") {
                        state.importPendingShared(replacingCurrent: false)
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
