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
            // Keep the margin minimal so the canvas fills as much space as possible
            let padding: CGFloat = 4
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
                        .clipShape(RoundedRectangle(cornerRadius: 4))
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
                    TapGesture().onEnded {
                        state.collapsePanel()
                        state.closeRatio()
                    }
                )
                // Drives the slide transition between pages
                .animation(.easeInOut(duration: 0.28), value: state.currentPageIndex)
            }
            .background(ColorManager.canvasAreaBackground.ignoresSafeArea())
            // Tapping anywhere on the canvas (outside the panels) dismisses an
            // open panel or the ratio sheet. Simultaneous so it never blocks
            // image pan/pinch/swap — a drag is not a tap, so those still win.
            .simultaneousGesture(
                TapGesture().onEnded {
                    state.collapsePanel()
                    state.closeRatio()
                }
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
            // Long-press action menu for an image box
            .confirmationDialog("Image",
                                isPresented: $state.showBoxActionMenu,
                                titleVisibility: .hidden) {
                Button("Replace") {
                    state.showReplacePicker = true
                }
                if let targetId = state.boxActionTargetId {
                    let source = state.pageIndex(containing: targetId)
                    ForEach(state.pages.indices, id: \.self) { pi in
                        if pi != source,
                           state.pages[pi].images.count < CollageState.maxImagesPerPage {
                            Button("Move to Page \(pi + 1)") {
                                state.moveImage(id: targetId, toPage: pi)
                                state.boxActionTargetId = nil
                            }
                        }
                    }
                    if state.pages.count < CollageState.maxPages {
                        Button("Move to New Page") {
                            state.moveImageToNewPage(id: targetId)
                            state.boxActionTargetId = nil
                        }
                    }
                }
                Button("Delete", role: .destructive) {
                    if let id = state.boxActionTargetId {
                        state.removeImage(id: id)
                    }
                    state.boxActionTargetId = nil
                }
                Button("Cancel", role: .cancel) {
                    state.boxActionTargetId = nil
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
            // Narrow edge zones for switching pages with a horizontal swipe.
            // Only these strips react, so image pan/swap gestures inside the
            // canvas are unaffected.
            .overlay {
                if state.pages.count > 1 {
                    HStack(spacing: 0) {
                        edgeSwipeStrip(isLeading: true)
                        Spacer(minLength: 0)
                        edgeSwipeStrip(isLeading: false)
                    }
                }
            }
        }
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

    /// 22pt-wide invisible strip at the canvas-area edge: swiping inward
    /// switches to the previous/next page.
    private func edgeSwipeStrip(isLeading: Bool) -> some View {
        Color.clear
            .frame(width: 22)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 15)
                    .onEnded { value in
                        let dx = value.translation.width
                        let before = state.currentPageIndex
                        withAnimation(.easeInOut(duration: 0.15)) {
                            if isLeading, dx > 30 {
                                // Swipe right from the left edge → previous page
                                state.currentPageIndex = max(state.currentPageIndex - 1, 0)
                            } else if !isLeading, dx < -30 {
                                // Swipe left from the right edge → next page
                                state.currentPageIndex = min(state.currentPageIndex + 1,
                                                             state.pages.count - 1)
                            }
                        }
                        #if canImport(UIKit)
                        if state.currentPageIndex != before {
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                        #endif
                    }
            )
    }
}

