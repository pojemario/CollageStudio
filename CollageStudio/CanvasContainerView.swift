import SwiftUI
import TipKit
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
    /// The page bar's height over the canvas (PageTabBar plus its margin).
    static let pagerHeight: CGFloat = 50

    var body: some View {
        GeometryReader { geo in
            // No margin at all — the canvas spreads edge to edge.
            let padding: CGFloat = 0
            let available = CGSize(
                width: geo.size.width - padding * 2,
                height: geo.size.height - padding * 2
            )
            // A carousel strip zoomed to one slide shows that slide with a
            // bit of its neighbours; otherwise the whole canvas fits.
            let focus = state.focusedSlide
            let slideW = state.pictureSize.width
            let shownW = focus == nil ? state.canvasSize.width : min(state.canvasSize.width, slideW * 1.2)
            let fitScale = min(available.width / max(shownW, 1),
                               available.height / max(state.canvasSize.height, 1))
            // The canvas is fit-to-screen and static: it is never zoomed or
            // rotated by gesture — only the images inside it are.
            let scale = fitScale
            let displayW = state.canvasSize.width * scale
            let displayH = state.canvasSize.height * scale
            // The part of the canvas on screen, and how far it's slid left.
            let windowW = min(displayW, available.width)
            let windowX: CGFloat = {
                guard let focus else { return 0 }
                let center = (CGFloat(focus) + 0.5) * slideW * scale
                return min(max(center - windowW / 2, 0), displayW - windowW)
            }()
            let contentW = max(windowW + padding * 2, geo.size.width)
            let contentH = max(displayH + padding * 2, geo.size.height)
            // Room above the collage for the page bar (shown with more than
            // one page), taken from the space left under it: all of the
            // bar's height if there's that much, else what there is (a tall
            // 9:16 collage keeps the bar floating over its top edge).
            let pagerReserve: CGFloat = state.pictureCount > 1 && !state.toolbarHidden
                ? min(Self.pagerHeight, max(geo.size.height - displayH, 0)) : 0

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
                // With only the collage showing, it sits in the middle.
                ZStack(alignment: state.toolbarHidden ? .center : .top) {
                    Color.clear

                    CollageGridView_Grid(scale: scale)
                        .padding(.top, state.toolbarHidden ? 0 : padding)
                        .frame(width: displayW, height: displayH)
                        // Before any images are added the canvas is invisible:
                        // one flat backdrop from the toolbar down, with just
                        // the "start" content on it.
                        .background(state.images.isEmpty ? AnyShapeStyle(.clear) : AnyShapeStyle(state.gapColor))
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
                        // Where the slides are cut (never exported).
                        .overlay {
                            if state.slides > 1 && state.hasAnyImages && !state.toolbarHidden {
                                SlideCuts(slides: state.slides)
                            }
                        }
                        // Only the zoomed-to slide (and its edges) shows.
                        // The window belongs to the page, so a page sliding
                        // out keeps its own view while the next slides in.
                        .offset(x: -windowX)
                        .frame(width: windowW, height: displayH, alignment: .leading)
                        .clipped()
                        // Fresh view identity per page: during the page
                        // transition SwiftUI briefly holds the outgoing and
                        // incoming canvas and slides between them
                        .id(state.currentPage.id)
                        .transition(.asymmetric(
                            insertion: .move(edge: state.pageSlideEdge).combined(with: .opacity),
                            removal: .move(edge: state.pageSlideEdge == .trailing ? .leading : .trailing)
                                .combined(with: .opacity)))
                        // Flatten the canvas into one layer first — otherwise
                        // .shadow draws a separate shadow under every image box
                        // (visible in the gaps) instead of just the outer edge.
                        .compositingGroup()
                        .shadow(color: state.images.isEmpty ? .clear : .black.opacity(0.25), radius: 20, x: 0, y: 8)
                        // A small anchor near the top of the collage for the
                        // tap-a-photo tip.
                        .overlay(alignment: .top) {
                            if state.hasAnyImages {
                                Color.clear.frame(width: 40, height: 1)
                                    .popoverTip(PhotoMenuTip(), arrowEdge: .bottom)
                                    .allowsHitTesting(false)
                                    .padding(.top, displayH * 0.3)
                            }
                        }
                        .animation(.spring(response: 0.4), value: state.canvasSize)
                        .animation(.spring(response: 0.4), value: state.numCols)
                        .animation(.spring(response: 0.4, dampingFraction: 0.9), value: state.focusedSlide)
                        .padding(.top, pagerReserve)
                        .animation(.easeInOut(duration: 0.25), value: pagerReserve)

                    // The empty space under the collage: a sideways swipe
                    // there steps posts, like the pager's arrows.
                    let freeBelow = contentH - (displayH + padding + pagerReserve)
                    if !state.toolbarHidden && state.pictureCount > 1 && freeBelow > 40 {
                        Color.clear
                            .contentShape(Rectangle())
                            .frame(height: freeBelow)
                            .gesture(
                                DragGesture(minimumDistance: 20)
                                    .onEnded { v in
                                        let dx = v.translation.width
                                        guard abs(dx) > 50, abs(dx) > abs(v.translation.height) * 1.5 else { return }
                                        state.stepPost(dx < 0 ? 1 : -1)
                                    }
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                            .accessibilityHidden(true)
                    }
                }
                .frame(width: contentW, height: contentH)
                .offset(y: textShift)
                .animation(.easeInOut(duration: 0.3), value: textShift)
                // (Taps here, gaps between images included, reach the canvas
                // area's tap handler below — once.)
                .contentShape(Rectangle())
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
            // While images load, a subtle gray spinner (over the start
            // screen too, after photos are picked or a collage is opened).
            .overlay {
                if state.isLoading || state.isRestoringProject {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.large)
                        .tint(.gray)
                        .opacity(0.55)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: state.isLoading)
            // No photos yet: the start screen — New Collage and the saved ones.
            .overlay {
                if !state.hasAnyImages && !state.isRestoringProject && !state.isLoading {
                    CollagesHome(store: state.projectStore) { showAddPicker = true }
                        .background(ColorManager.canvasAreaBackground.ignoresSafeArea())
                        .transition(.opacity)
                }
            }
            .photosPicker(isPresented: $showAddPicker,
                          selection: $photoItems,
                          maxSelectionCount: 30,
                          matching: .images)
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
            // Round buttons on the pager's line, filling in from the right:
            // hold to see the collage without its edits, effects and filter;
            // on a spread page, zoom out to the whole spread or in to a post.
            .overlay(alignment: .topTrailing) {
                let photoToolsUp = CollageState.photoToolsAtTop && state.selectedImage != nil
                let compare = state.hasAnyImages && state.hasLookEdits
                let spread = state.hasAnyImages && state.slides > 1
                if !state.toolbarHidden && !photoToolsUp && (compare || spread) {
                    HStack(spacing: 8) {
                        if spread { SpreadZoomButton().transition(.opacity) }
                        if compare { CompareButton().transition(.opacity) }
                    }
                    // Centered on the pager's line (pager: 40 tall, 2 down).
                    .padding(.top, 3)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { f in
                        guard f.differs(from: state.compareButtonFrame) else { return }
                        Diagnostics.count("compareButtonFrame")
                        state.compareButtonFrame = f
                    }
                    .onDisappear { state.compareButtonFrame = .zero }
                    .padding(.trailing, 10)
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: state.slides > 1)
            .animation(.easeInOut(duration: 0.2), value: state.hasLookEdits)
            .onChange(of: photoItems) { _, newItems in
                loadPhotos(newItems)
            }
            .onChange(of: geo.frame(in: .global), initial: true) { _, f in
                guard f.differs(from: state.canvasVisibleRect) else { return }
                Diagnostics.count("canvasVisibleRect")
                state.canvasVisibleRect = f
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
    // MARK: - Load photos (New Collage on the start screen)

    func loadPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        state.isBusy = true
        state.isLoading = true
        Diagnostics.log("adding \(items.count) photos")
        Task {
            let start = Date()
            let prepared = await CollageImage.prepare(items)
            Diagnostics.log(String(format: "read %d of %d photos in %.1fs", prepared.count, items.count, Date().timeIntervalSince(start)))
            await MainActor.run {
                let isNew = !state.hasAnyImages
                Diagnostics.log(String(format: "prepared photos in %.1fs", Date().timeIntervalSince(start)))
                state.addPreparedImages(prepared)
                if isNew && state.hasAnyImages { state.openImagesPanel() }
                Diagnostics.log("added photos · \(state.diagnosticsSummary)")
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
            // Decoded and prepared off the main thread.
            if let prepared = await CollageImage.prepare([item]).first {
                await MainActor.run {
                    state.replaceImage(id: targetId, with: prepared)
                }
            }
            await MainActor.run {
                replaceItems = []
                state.boxActionTargetId = nil
            }
        }
    }

}


/// Press and hold: the collage without its edits, effects and filter.
/// On a spread page: the whole spread at once, or one post at a time.
private struct SpreadZoomButton: View {
    @EnvironmentObject var state: CollageState

    var body: some View {
        let whole = state.focusedSlide == nil
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                state.slideFocus = whole ? 0 : nil
            }
        } label: {
            Image(systemName: whole ? "plus.magnifyingglass" : "minus.magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)
                .frame(width: 38, height: 38)
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().strokeBorder(ColorManager.glassStroke, lineWidth: 0.8))
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(whole ? "One post at a time" : "Whole spread")
    }
}

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

/// The cuts between a carousel's slides: dashed lines over the canvas, with
/// each slide's number at its top. Only on screen.
struct SlideCuts: View {
    let slides: Int

    var body: some View {
        GeometryReader { g in
            let w = g.size.width / CGFloat(max(slides, 1))
            ZStack(alignment: .topLeading) {
                Path { p in
                    for i in 1..<slides {
                        let x = (w * CGFloat(i)).rounded()
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: g.size.height))
                    }
                }
                // White under dark: reads on light and dark photos alike.
                .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 2.25, dash: [6, 4]))
                .shadow(color: .black.opacity(0.45), radius: 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
