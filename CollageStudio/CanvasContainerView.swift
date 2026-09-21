import SwiftUI
#if canImport(PhotosUI)
import PhotosUI
#endif

/// Springy press feedback for the big empty-canvas "add images" button.
struct PressBounceStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.5), value: configuration.isPressed)
    }
}

struct CanvasContainerView: View {
    @EnvironmentObject var state: CollageState
    @Environment(\.colorScheme) private var colorScheme
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var replaceItems: [PhotosPickerItem] = []
    @State private var showAddPicker = false

    var body: some View {
        GeometryReader { geo in
            // No margin at all — the canvas spreads edge to edge.
            let padding: CGFloat = 0
            let available = CGSize(
                width: geo.size.width - padding * 2,
                height: geo.size.height - padding * 2
            )
            let fitScale = min(available.width / max(state.canvasSize.width, 1),
                               available.height / max(state.canvasSize.height, 1))
            // The canvas is fit-to-screen and static: it is never zoomed or
            // rotated by gesture — only the images inside it are.
            let scale = fitScale
            let displayW = state.canvasSize.width * scale
            let displayH = state.canvasSize.height * scale
            let contentW = max(displayW + padding * 2, geo.size.width)
            let contentH = max(displayH + padding * 2, geo.size.height)

            ScrollView([.horizontal, .vertical]) {
                // Dock the canvas to the top (not vertically centered) so its
                // top edge is always fully visible, even with the panel open.
                ZStack(alignment: .top) {
                    Color.clear

                    CollageGridView_Grid(scale: scale)
                        .padding(.top, padding)
                        // Fresh view identity per page: during the page
                        // transition SwiftUI briefly holds the outgoing and
                        // incoming canvas and slides between them
                        .id(state.currentPage.id)
                        .transition(.push(from: state.pageSlideEdge))
                        .frame(width: displayW, height: displayH)
                        // Before any images are added the canvas is transparent
                        // so the app background shows behind the "add" button.
                        .background(state.images.isEmpty ? AnyShapeStyle(.clear) : AnyShapeStyle(state.gapColor))
                        // Flatten the canvas into one layer first — otherwise
                        // .shadow draws a separate shadow under every image box
                        // (visible in the gaps) instead of just the outer edge.
                        .compositingGroup()
                        .shadow(color: state.images.isEmpty ? .clear : .black.opacity(0.25), radius: 20, x: 0, y: 8)
                        // When the canvas is empty, the whole canvas acts as an
                        // "Add Images" button. Once at least one image exists,
                        // this overlay disappears and tapping does nothing.
                        .overlay {
                            if state.images.isEmpty {
                                Button {
                                    showAddPicker = true
                                } label: {
                                    VStack(spacing: 16) {
                                        Image(systemName: "plus")
                                            .font(.system(size: 44, weight: .medium))
                                            .foregroundColor(.white)
                                            .frame(width: 96, height: 96)
                                            .background(
                                                RoundedRectangle(cornerRadius: 28, style: .continuous)
                                                    .fill(Color.accentColor)
                                                    .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                                            )
                                        Text("Add images to start")
                                            .font(.callout)
                                            .foregroundColor(.black.opacity(0.6))
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    // Bias toward the top so the button stays
                                    // visible above the bottom panel.
                                    .offset(y: -displayH * 0.18)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(PressBounceStyle())
                                .photosPicker(isPresented: $showAddPicker,
                                              selection: $photoItems,
                                              maxSelectionCount: 30,
                                              matching: .images)
                            }
                        }
                        .coordinateSpace(name: "collageCanvas")
                        .animation(.spring(response: 0.4), value: state.canvasSize)
                        .animation(.spring(response: 0.4), value: state.numCols)
                }
                .frame(width: contentW, height: contentH)
                // Any tap on the canvas area (including the gaps/separators
                // between images) dismisses an open panel or ratio sheet.
                // Simultaneous so image pan/pinch/swap still win on a drag.
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture().onEnded { state.handleCanvasTap() }
                )
                // Drives the slide transition between pages
                .animation(.easeInOut(duration: 0.28), value: state.currentPageIndex)
            }
            .background(ColorManager.canvasAreaBackground.ignoresSafeArea())
            // Tapping anywhere on the canvas (outside the panels) dismisses an
            // open panel or the ratio sheet. Simultaneous so it never blocks
            // image pan/pinch/swap — a drag is not a tap, so those still win.
            .simultaneousGesture(
                TapGesture().onEnded { state.handleCanvasTap() }
            )
            // The canvas is static: user interaction never pans it
            .scrollDisabled(true)
            .scrollIndicators(.hidden, axes: [.horizontal, .vertical])
            // Subtle gray spinner over the canvas while images are loading
            .overlay {
                if state.isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.large)
                        .tint(.gray)
                        .opacity(0.55)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: state.isLoading)
            .onChange(of: photoItems) { _, newItems in
                loadPhotos(newItems)
            }
            // Long-press action menu: ONE popover on this stable container,
            // anchored at the recorded press point (canvas space → this view's
            // local space: the grid sits top-centered in the content area).
            // Per-box popovers must not be used — after swaps they left
            // orphaned UIKit presentation views over the box that swallowed
            // all its touches.
            .popover(isPresented: actionMenuShown,
                     attachmentAnchor: .rect(.rect(CGRect(
                        x: state.boxActionPressPoint.x + (contentW - displayW) / 2,
                        y: state.boxActionPressPoint.y + padding,
                        width: 1, height: 1)))) {
                if let id = state.boxActionTargetId {
                    BoxActionMenu(imageId: id)
                        .environmentObject(state)
                        .presentationCompactAdaptation(.popover)
                }
            }
            // Single-image picker for the "Replace" action
            .photosPicker(isPresented: $state.showReplacePicker,
                          selection: $replaceItems,
                          maxSelectionCount: 1,
                          matching: .images)
            .onChange(of: replaceItems) { _, newItems in
                loadReplacement(newItems)
            }
        }
    }
    /// Dismissing the action menu (tap outside) clears the target unless the
    /// Replace picker took over.
    private var actionMenuShown: Binding<Bool> {
        Binding(
            get: { state.showBoxActionMenu },
            set: { shown in
                if !shown {
                    state.showBoxActionMenu = false
                    if !state.showReplacePicker { state.boxActionTargetId = nil }
                }
            }
        )
    }

    // MARK: - Load photos (empty-canvas add button)

    func loadPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        state.isBusy = true
        state.isLoading = true
        Task {
            var loaded: [PlatformImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = PlatformImage(data: data) {
                    loaded.append(img)
                }
            }
            // Generate proxies/thumbnails off the main thread
            let images = loaded
            let prepared = await Task.detached(priority: .userInitiated) {
                images.map { CollageImage(image: $0) }
            }.value
            await MainActor.run {
                state.addPreparedImages(prepared)
                photoItems = []
                state.isBusy = false
                state.isLoading = false
            }
        }
    }

    func loadReplacement(_ items: [PhotosPickerItem]) {
        guard let item = items.first,
              let targetId = state.boxActionTargetId else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let img = PlatformImage(data: data) {
                await MainActor.run {
                    state.replaceImage(id: targetId, with: img)
                }
            }
            await MainActor.run {
                replaceItems = []
                state.boxActionTargetId = nil
            }
        }
    }

}

