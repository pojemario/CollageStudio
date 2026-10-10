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

            // While a text box is edited, the canvas slides up just enough to
            // keep that box in the part of the screen the panel (and
            // keyboard) leave free, so every change is seen live.
            let textShift: CGFloat = {
                guard let id = state.textEditTargetId, let box = state.imageFrame(for: id) else { return 0 }
                let top = geo.frame(in: .global).minY
                let visible: CGFloat = state.isPanelOpen && state.panelTopGlobalY > top
                    ? max(state.panelTopGlobalY - top, 120)
                    : max(geo.size.height - FloatingTabBar.zoneHeight, 120)
                guard displayH > visible else { return 0 }
                let wanted = visible / 2 - box.midY
                return min(max(wanted, -(displayH - visible)), 0)
            }()

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
                        .transition(.asymmetric(
                            insertion: .move(edge: state.pageSlideEdge).combined(with: .opacity),
                            removal: .move(edge: state.pageSlideEdge == .trailing ? .leading : .trailing)
                                .combined(with: .opacity)))
                        .frame(width: displayW, height: displayH)
                        // Before any images are added the canvas is invisible:
                        // one flat backdrop from the toolbar down, with just
                        // the "start" content on it.
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
                                    EmptyCanvasContent(canvasSize: CGSize(width: displayW, height: displayH))
                                }
                                .buttonStyle(PressBounceStyle())
                                .photosPicker(isPresented: $showAddPicker,
                                              selection: $photoItems,
                                              maxSelectionCount: 30,
                                              matching: .images)
                            }
                        }
                        .coordinateSpace(name: "collageCanvas")
                        // Insert marker: a bar across the hovered splitter.
                        .overlay(alignment: .topLeading) {
                            if let target = state.dropInsertTarget {
                                // Across a column's gap, or down a row's.
                                let across = !state.isRows
                                Capsule()
                                    .fill(Color.accentColor)
                                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5))
                                    .frame(width: across ? max(target.frame.width - 8, 20) : 8,
                                           height: across ? 8 : max(target.frame.height - 8, 20))
                                    .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
                                    .position(x: target.frame.midX, y: target.frame.midY)
                                    .allowsHitTesting(false)
                                    .transition(.opacity)
                            }
                        }
                        .animation(.easeOut(duration: 0.12), value: state.dropInsertTarget)
                        .animation(.spring(response: 0.4), value: state.canvasSize)
                        .animation(.spring(response: 0.4), value: state.numCols)
                }
                .frame(width: contentW, height: contentH)
                .offset(y: textShift)
                .animation(.easeInOut(duration: 0.3), value: textShift)
                // Any tap on the canvas area (including the gaps/separators
                // between images) dismisses an open panel or ratio sheet.
                // Simultaneous so image pan/pinch/swap still win on a drag.
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture().onEnded { state.handleCanvasTap() }
                )
                // Drives the slide transition between pages
                .animation(.easeInOut(duration: 0.3), value: state.currentPageIndex)
                // Pages slide within the canvas area, never over the chrome.
                .clipped()
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
            // While images load: on the empty start page the plus in the
            // ring spins instead (see EmptyCanvasContent); once there is a
            // collage, a subtle gray spinner over it.
            .overlay {
                if state.isLoading && !state.images.isEmpty {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.large)
                        .tint(.gray)
                        .opacity(0.55)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: state.isLoading)
            // Start screen: saved collages are one tap away.
            .overlay(alignment: .bottom) {
                if !state.hasAnyImages && !state.isRestoringProject {
                    RecentCollagesButton(store: state.projectStore)
                        .padding(.bottom, 24)
                }
            }
            // Before / after peek (holding a filter tile). Only the badge
            // fades — the pictures themselves switch instantly (animating
            // the whole canvas made the swap flash).
            .overlay(alignment: .top) {
                ZStack {
                    if state.filterBypass || state.compareOriginal {
                        Text("Before")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.black.opacity(0.55)))
                            .padding(.top, 12)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.12), value: state.filterBypass)
                .animation(.easeInOut(duration: 0.12), value: state.compareOriginal)
                .allowsHitTesting(false)
            }
            // Hold to see the collage without its edits, effects and filter.
            .overlay(alignment: .topTrailing) {
                if state.hasAnyImages && state.hasLookEdits && !state.toolbarHidden {
                    CompareButton()
                        .padding(.top, 10)
                        .padding(.trailing, 10)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: state.hasLookEdits)
            .onChange(of: photoItems) { _, newItems in
                loadPhotos(newItems)
            }
            // Where canvas space sits on screen, for the long-press action
            // menu — drawn at the app's root (BoxActionMenuLayer) so it floats
            // above the bottom panel too. The grid sits top-centered in the
            // content area.
            .onChange(of: CGPoint(x: geo.frame(in: .global).minX + (contentW - displayW) / 2,
                                  y: geo.frame(in: .global).minY + padding),
                      initial: true) { _, origin in
                state.boxActionCanvasOrigin = origin
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


/// What an empty canvas shows: a big thin plus in a hairline ring, gently
/// breathing, with a one-line hint. The whole canvas is the button.
private struct EmptyCanvasContent: View {
    @EnvironmentObject var state: CollageState
    let canvasSize: CGSize
    @State private var breathing = false
    /// Keeps turning while photos load — the start page's own spinner.
    @State private var spinning = false

    /// Natural size of the plus ring + "ADD PHOTOS" stack.
    private static let promptSize = CGSize(width: 330, height: 220)

    var body: some View {
        // Dashed outline in the canvas ratio, so the chosen format is visible
        // before any photos are in. Centered, with the prompt inside it.
        let aspect = max(state.canvasSize.width, 1) / max(state.canvasSize.height, 1)
        let box = CGSize(width: canvasSize.width * 0.84, height: canvasSize.height * 0.84)
        let rect = aspect > box.width / box.height
            ? CGSize(width: box.width, height: box.width / aspect)
            : CGSize(width: box.height * aspect, height: box.height)
        // Wide formats leave little height: shrink the prompt to fit inside.
        let promptScale = min(1, (rect.width - 32) / Self.promptSize.width,
                              (rect.height - 32) / Self.promptSize.height)

        ZStack {
            RoundedRectangle(cornerRadius: ButtonStyleGuide.cornerRadius, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.3),
                              style: StrokeStyle(lineWidth: 1.5, dash: [7, 6]))
                .frame(width: rect.width, height: rect.height)

            prompt
                .scaleEffect(max(promptScale, 0.3))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
    }

    private var prompt: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1.5)
                    .frame(width: 148, height: 148)
                    .scaleEffect(breathing ? 1.05 : 1)
                    .opacity(breathing ? 0.7 : 1)
                Image(systemName: "plus")
                    .font(.system(size: 64, weight: .thin))
                    .foregroundColor(.accentColor)
                    .rotationEffect(.degrees(spinning ? 360 : 0))
                    .animation(spinning
                               ? .linear(duration: 1.2).repeatForever(autoreverses: false)
                               : .easeOut(duration: 0.4),
                               value: spinning)
            }
            .onChange(of: state.isLoading, initial: true) { _, loading in
                spinning = loading
            }
            Text("ADD PHOTOS")
                .font(.system(size: 38, weight: .ultraLight))
                .tracking(6)
                .foregroundColor(.accentColor)
                .fixedSize()
        }
    }
}

/// Press and hold: the collage without its edits, effects and filter.
private struct CompareButton: View {
    @EnvironmentObject var state: CollageState
    @GestureState private var holding = false

    var body: some View {
        Image(systemName: "square.split.2x1")
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(holding ? .white : .primary)
            .frame(width: 38, height: 38)
            .background(Circle().fill(holding ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.ultraThinMaterial)))
            .overlay(Circle().strokeBorder(ColorManager.glassStroke, lineWidth: 0.8))
            .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
            .scaleEffect(holding ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: holding)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($holding) { _, holding, _ in holding = true }
            )
            .onChange(of: holding) { _, down in
                state.compareOriginal = down
                #if canImport(UIKit)
                if down { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                #endif
            }
            .accessibilityLabel("Compare with original")
            .accessibilityHint("Touch and hold to see the photos without edits, effects and filter")
            .accessibilityAddTraits(.isButton)
    }
}
