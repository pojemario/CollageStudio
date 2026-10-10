import SwiftUI
#if canImport(PhotosUI)
import PhotosUI
#endif

/// The floating tab pill at the bottom of the phone layout: one glass
/// capsule, always visible while there are images, a tab per panel. Tapping
/// a tab raises the panel card above it; tapping the open tab again lowers
/// it. The active tab sits in a lens that slides between tabs; dragging
/// across the pill lifts the lens into clear glass that follows the finger,
/// and letting go opens the tab under it.
struct FloatingTabBar: View {
    @EnvironmentObject var state: CollageState
    /// True while the panel card is up: the pill drops its own glass and
    /// becomes the bottom row of the card, behind an inset separator.
    var merged = false

    /// Width of the tab row, for turning a finger position into a tab.
    @State private var rowWidth: CGFloat = 0
    /// Finger x (in the tab row) while scrubbing; nil otherwise.
    @State private var scrubX: CGFloat?
    /// Tab under the finger while scrubbing, for the haptic tick.
    @State private var hoverTab: Int?

    static let tabs = ["Images", "Layout", "Canvas", "Frames", "Overlay", "Edit", "Filter"]
    static let icons = ["photo.on.rectangle.angled", "square.grid.2x2", "rectangle.inset.filled",
                        "photo.artframe", "sparkles", "wand.and.stars", "camera.filters"]
    /// Vertical room the pill takes at the bottom of the screen (pill +
    /// its margins) — what the panel card and the canvas leave free.
    static let zoneHeight: CGFloat = 80
    /// Gap between the pill and the bottom safe area; slightly negative so
    /// the pill dips a little into the home-indicator area.
    static let bottomMargin: CGFloat = -4
    /// Extra room between the panel content and the tab row while the panel
    /// is open; the pill itself never moves.
    static let openLift: CGFloat = 0
    /// Corner radius of the pill, and of the card it merges into.
    static let cornerRadius: CGFloat = 24
    /// Horizontal travel before a touch becomes a scrub instead of a tap.
    private static let scrubThreshold: CGFloat = 8
    private static let rowSpace = "FloatingTabBar.row"
    private static let tabHeight: CGFloat = 50

    /// The chosen tab keeps its lens even while its panel is lowered, so
    /// the pill always shows which tools are one tap away.
    private var activeTab: Int { state.selectedPanelTab }
    private var scrubbing: Bool { scrubX != nil }
    private var tabWidth: CGFloat { rowWidth / CGFloat(Self.tabs.count) }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Self.tabs.indices, id: \.self) { i in
                tabLabel(i)
            }
        }
        .background(alignment: .leading) { lens }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
        .coordinateSpace(.named(Self.rowSpace))
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
        .gesture(scrubGesture)
        .background {
            if !merged { pillGlass }
        }
        // Inset separator between the card's content and its tab row.
        .overlay(alignment: .top) {
            if merged {
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(height: 1)
                    .padding(.horizontal, 14)
                    .offset(y: -5)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: activeTab)
        .animation(.spring(response: 0.3, dampingFraction: 0.68), value: scrubbing)
        .animation(.easeInOut(duration: 0.25), value: merged)
        .padding(.horizontal, 10)
        .padding(.bottom, Self.bottomMargin)
    }

    private func tabLabel(_ i: Int) -> some View {
        // Idle: the active tab is white on the accent lens. Scrubbing: the
        // lens turns clear and the tab under it takes the accent color.
        let onChip = !scrubbing && activeTab == i
        let hovered = scrubbing && hoverTab == i
        return VStack(spacing: 3) {
            Image(systemName: Self.icons[i])
                .font(.system(size: 19, weight: onChip || hovered ? .medium : .regular))
                .frame(height: 24)
            Text(Self.tabs[i])
                .font(.system(size: 9.5, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 8)
        .foregroundStyle(onChip ? Color.white : hovered ? Color.accentColor : Color.primary.opacity(0.72))
        .scaleEffect(hovered ? 1.12 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovered)
        .frame(maxWidth: .infinity)
        .frame(height: Self.tabHeight)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(activeTab == i ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { select(i) }
    }

    /// The selection lens: a solid accent chip at rest, so the active tab
    /// reads at a glance over any canvas; lifted, larger clear glass while
    /// scrubbing, tracking the finger.
    private var lens: some View {
        let shape = RoundedRectangle(cornerRadius: ButtonStyleGuide.cornerRadius, style: .continuous)
        let center = scrubX.map { min(max($0, tabWidth / 2), rowWidth - tabWidth / 2) }
            ?? (CGFloat(activeTab) + 0.5) * tabWidth
        return ZStack {
            shape
                .fill(LinearGradient(colors: [Color.accentColor.opacity(0.85), Color.accentColor],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(shape.strokeBorder(Color.white.opacity(0.35), lineWidth: 0.8))
                .shadow(color: Color.accentColor.opacity(0.45), radius: 6, y: 2)
                .opacity(scrubbing ? 0 : 1)
            clearGlass(shape)
                .opacity(scrubbing ? 1 : 0)
        }
        .frame(width: tabWidth, height: Self.tabHeight)
        .scaleEffect(scrubbing ? CGSize(width: 1.22, height: 1.3) : CGSize(width: 1, height: 1))
        .offset(x: center - tabWidth / 2)
        // Glued to the finger while scrubbing; a spring otherwise.
        .animation(scrubbing ? .interactiveSpring(response: 0.18, dampingFraction: 0.86) : nil, value: scrubX)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func clearGlass(_ shape: RoundedRectangle) -> some View {
        if #available(iOS 26, macOS 26, *) {
            Color.clear.glassEffect(.clear, in: shape)
        } else {
            shape
                .fill(.ultraThinMaterial)
                .overlay(shape.strokeBorder(ColorManager.glassStroke, lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        }
    }

    @ViewBuilder
    private var pillGlass: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        if #available(iOS 26, macOS 26, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            shape
                .fill(.ultraThinMaterial)
                .overlay(shape.strokeBorder(ColorManager.glassStroke, lineWidth: 0.8))
                .shadow(color: .black.opacity(0.14), radius: 16, y: 6)
        }
    }

    /// One gesture for the whole pill: a touch that stays put is a tap on
    /// the tab under it; one that travels sideways scrubs the lens.
    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.rowSpace))
            .onChanged { v in
                if !scrubbing {
                    guard abs(v.translation.width) > Self.scrubThreshold else { return }
                    hoverTab = tab(at: v.location.x)
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    #endif
                }
                scrubX = v.location.x
                let i = tab(at: v.location.x)
                if i != hoverTab {
                    hoverTab = i
                    #if canImport(UIKit)
                    UISelectionFeedbackGenerator().selectionChanged()
                    #endif
                }
            }
            .onEnded { v in
                let i = tab(at: v.location.x)
                if scrubbing {
                    // A scrub always lands open on its tab, never toggles it shut.
                    select(i, toggles: false)
                    scrubX = nil
                    hoverTab = nil
                } else {
                    select(i)
                }
            }
    }

    private func tab(at x: CGFloat) -> Int {
        guard tabWidth > 0 else { return activeTab }
        return min(max(Int(x / tabWidth), 0), Self.tabs.count - 1)
    }

    private func select(_ i: Int, toggles: Bool = true) {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        state.closeRatio()
        if state.textEditTargetId != nil || state.protrusionTargetId != nil {
            // Any tab leaves text / protrusion editing and shows that tab.
            state.endTextEditing()
            state.endProtrusionEditing()
            state.selectedPanelTab = i
        } else if toggles && state.selectedPanelTab == i && state.isPanelOpen {
            withAnimation(.easeInOut(duration: 0.25)) { state.isPanelOpen = false }
        } else {
            state.selectedPanelTab = i
            withAnimation(.easeInOut(duration: 0.25)) { state.isPanelOpen = true }
        }
    }
}

/// The panel card: the content of the selected tab on a floating glass
/// sheet that rises above the tab pill.
struct BottomPanelView: View {
    @EnvironmentObject var state: CollageState
    @State private var showOneOnOneConfirm = false
    @State private var showBurstConfirm = false
    @State private var showBurstAllConfirm = false
    @State private var showAllOnOneConfirm = false
    @State private var pagesContentHeight: CGFloat = 0

    /// Natural height of the panel content, and how much of it shows.
    @State private var contentHeight: CGFloat = 0
    @State private var shownHeight: CGFloat = 0
    /// Content height while the grabber is being dragged (and while it
    /// settles after); nil otherwise.
    @State private var liveCap: CGFloat?
    @State private var dragStartHeight: CGFloat?
    @State private var cardHeight: CGFloat = 0

    /// The smallest the panel can be dragged to (about one row of content).
    private static let minHeight: CGFloat = 80
    /// Within this of the full height a released drag snaps to full.
    private static let fullSnap: CGFloat = 28

    /// Each tab (and the text / protrusion editors) keeps its own size; one
    /// not resized yet shows at full height.
    private var capKey: Int {
        if state.textEditTargetId != nil { return -1 }
        if state.protrusionTargetId != nil { return -2 }
        return state.selectedPanelTab
    }

    private let card = RoundedRectangle(cornerRadius: FloatingTabBar.cornerRadius, style: .continuous)
    /// While up, the card's glass reaches down around the tab pill so the
    /// two read as one piece (see FloatingTabBar.merged).
    private var merged: Bool { state.isPanelOpen && state.panelDrag == 0 }
    /// Shorter than its content: the content scrolls.
    private var scrolls: Bool { contentHeight > shownHeight + 1 }

    var body: some View {
        VStack(spacing: 0) {
            // Grabber: drag it to size the panel (it stays where it's left,
            // and the content scrolls when it doesn't all fit). It doesn't
            // close the panel: tapping the open tab does.
            Capsule()
                .fill(Color.primary.opacity(0.22))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                // A taller touch area, reaching over the content's top padding.
                .padding(.bottom, -6)
                .panelChrome(state)
                .gesture(resizeGesture)
                .zIndex(1)

            // Panel content — each tab is only as tall as its own content,
            // or as the size the panel was dragged to.
            CappedHeight(cap: liveCap ?? state.panelCaps[capKey] ?? .infinity) {
                ScrollView(.vertical) {
                    panelContent
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                }
                .scrollDisabled(!scrolls || state.activeAdjustment != nil)
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(scrolls ? .automatic : .hidden)
                // Full size: nothing is clipped (row highlights and shadows
                // reach past the edges, as before).
                .scrollClipDisabled(!scrolls)
                // Cut short: the content fades out at the edges.
                .mask {
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                            .frame(height: scrolls ? 10 : 0)
                        Color.black
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: scrolls ? 14 : 0)
                    }
                    // Never clips sideways; vertically only when cut short.
                    .padding(.horizontal, -40)
                    .padding(.vertical, scrolls ? 0 : -40)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { shownHeight = $0 }
            .environment(\.panelScrolls, scrolls)
        }
        // Floating glass card. Fades while adjusting a slider so the collage
        // shows through; lives here so the drag offset moves it with the content.
        .background {
            card
                .fill(.ultraThinMaterial)
                .overlay(card.strokeBorder(ColorManager.glassStroke, lineWidth: 0.8))
                .shadow(color: .black.opacity(0.12), radius: 18, y: 6)
                .padding(.bottom, merged ? -(FloatingTabBar.zoneHeight - FloatingTabBar.bottomMargin + FloatingTabBar.openLift) : 0)
                .animation(.easeInOut(duration: 0.25), value: merged)
                .opacity(state.activeAdjustment == nil && !state.shuffleFocusActive ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: state.activeAdjustment)
        }
        // Report the card's height so it knows how far to slide to be fully
        // hidden: past the tab bar zone and the home-indicator area. Not
        // while the grabber is dragged (that would redraw the whole app
        // every frame); the drag reports it when it ends.
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
            cardHeight = h
            if !state.isPanelDragging { state.panelHeight = h + FloatingTabBar.zoneHeight + 60 }
        }
    }

    @ViewBuilder
    private var panelContent: some View {
        Group {
            // Editing a text box takes over the panel until it's done.
            if let textId = state.textEditTargetId {
                TextEditPanel(imageId: textId)
            } else if let protrudeId = state.protrusionTargetId {
                // So does a photo's protrusion (long-press → Protrude).
                ProtrusionPanel(imageId: protrudeId)
            } else {
                switch state.selectedPanelTab {
                case 0: imagesTab
                case 1: layoutTab
                case 2: borderTab
                case 3: framesTab
                case 4: overlayTab
                case 5: effectsTab
                default: FilterControls()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    /// The panel follows the finger, between about one row and its full
    /// height; past the smallest size it resists and springs back. Released
    /// close to full it snaps to full, anywhere else it stays (for this tab).
    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { v in
                if dragStartHeight == nil {
                    dragStartHeight = shownHeight
                    state.isPanelDragging = true
                }
                let floor = min(Self.minHeight, contentHeight)
                let raw = (dragStartHeight ?? shownHeight) - v.translation.height
                // Rubber band below the smallest size.
                let h = raw >= floor ? raw : floor - min((floor - raw) * 0.25, 24)
                liveCap = min(h, contentHeight)
            }
            .onEnded { _ in
                let floor = min(Self.minHeight, contentHeight)
                let h = liveCap ?? shownHeight
                let key = capKey
                dragStartHeight = nil
                if h >= contentHeight - Self.fullSnap {
                    settle(to: contentHeight) { state.panelCaps[key] = nil }
                } else if h < floor {
                    settle(to: floor) { state.panelCaps[key] = floor }
                } else {
                    state.panelCaps[key] = h
                    liveCap = nil
                }
                state.isPanelDragging = false
                state.panelHeight = cardHeight + FloatingTabBar.zoneHeight + 60
            }
    }

    /// Springs the live height to `height`, then hands over to the stored size.
    private func settle(to height: CGFloat, then store: @escaping () -> Void) {
        withAnimation(.snappy(duration: 0.22)) {
            liveCap = height
        } completion: {
            store()
            liveCap = nil
        }
    }

    // MARK: - Images tab

    var imagesTab: some View {
        VStack(spacing: 10) {
            // Fixed button bar — does not scroll with the page list
            HStack(spacing: 8) {
                AddPageTile { state.addPage() }
                    .disabled(state.pages.count >= CollageState.maxPages)
                    .opacity(state.pages.count >= CollageState.maxPages ? 0.5 : 1)

                // Adds an editable text box rendered as an image.
                ToolbarTile(sf: "character.textbox", title: "Text") { state.addTextImage() }

                // Adds a transparent placeholder — an intentional empty slot.
                ToolbarTile(sf: "rectangle.dashed.badge.record", title: "Empty") { state.addEmptyImage() }

                SpreadMenuButton(
                    onBurst: { showBurstConfirm = true },
                    onOnePerPage: { showOneOnOneConfirm = true },
                    onAllOnOne: { showAllOnOneConfirm = true },
                    onBurstAll: { showBurstAllConfirm = true })

                // Saved collages and "New Collage" (the open one is kept).
                ToolbarTile(sf: "square.stack", title: "Collages", prominent: false) { state.showProjects = true }
            }
            .alert("Burst!", isPresented: $showBurstAllConfirm) {
                Button("Proceed") { state.burstBalanced() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will spread all \(state.totalImageCount) images across \(state.burstPageCount) balanced page\(state.burstPageCount == 1 ? "" : "s"), do you want to proceed?")
            }
            .alert("One image per page", isPresented: $showOneOnOneConfirm) {
                Button("Proceed") { state.distributeOneImagePerPage() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will add 1 image per 1 page, do you want to proceed?")
            }
            .alert("Spread images across pages", isPresented: $showBurstConfirm) {
                Button("Proceed") { state.burstAcrossPages() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will distribute all images evenly across the \(state.pages.count) page\(state.pages.count == 1 ? "" : "s"), do you want to proceed?")
            }
            .alert("All images on one page", isPresented: $showAllOnOneConfirm) {
                Button("Proceed") { state.mergeAllOntoOnePage() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will put all images on a single page and remove the other pages, do you want to proceed?")
            }

            // The page list hugs its content (one row for a single page) and
            // only scrolls once it would exceed the cap — no empty space below.
            ScrollView {
                PageGroupsView()
                    .background(
                        GeometryReader { g in
                            Color.clear
                                .onAppear { pagesContentHeight = g.size.height }
                                .onChange(of: g.size.height) { _, h in pagesContentHeight = h }
                        }
                    )
            }
            .frame(height: min(pagesContentHeight, 220))
        }
    }

    // MARK: - Layout tab

    var layoutTab: some View {
        VStack(spacing: 10) {
            // Whole looks in one tap, and the user's saved ones.
            StylePresetsRow()

            VStack(spacing: 10) {
                LabeledSlider(label: "Columns", value: Binding(
                    get: { Double(min(state.numCols, state.maxSelectableCols)) },
                    set: { v in state.numCols = Int(v); state.rebuildLayout(resetGrows: true) }
                ), range: 1...Double(state.maxSelectableCols), step: 1, format: "%.0f", resetValue: 2,
                   reservesSwatchSlot: true, customLabel: AnyView(LanesSwitch()),
                   compactValue: true)
                    .disabled(state.maxSelectableCols <= 1)
                    .opacity(state.maxSelectableCols <= 1 ? 0.4 : 1)

                LabeledSlider(label: "Spacing", value: $state.gap, range: 0...70, step: 1, format: "%.0f",
                              resetValue: 10, swatchColor: $state.backgroundColor,
                              compactValue: true)

                LabeledSlider(label: "Rounding", value: $state.cornerRadius, range: 0...100, step: 1, format: "%.0f",
                              resetValue: 20, reservesSwatchSlot: true,
                              compactValue: true)

                BorderStyleRow()

                BorderPlacementRow()
            }
            // No Reset button: swipe up or down on the labels or numbers.
            .swipeNumbersToReset(canReset: state.hasStyleChanges) { state.resetStyle() }

            HStack(spacing: 8) {
                // Shuffle stays visible in shuffle-focus mode; the others fade.
                ShuffleButton().panelChrome(state, keep: "Shuffle")
                // Only meaningful with more than one page — hidden visually on a
                // single page but keeps its slot so the other buttons don't move.
                ActionButton(label: "Apply to All", sf: "square.on.square") { state.applyStyleToAllPages() }
                    .disabled(!state.canApplyToAll || state.pages.count <= 1)
                    .opacity(state.pages.count <= 1 ? 0 : (state.canApplyToAll ? 1 : 0.5))
                    .allowsHitTesting(state.pages.count > 1)
                    .panelChrome(state)
            }
        }
    }

    // MARK: - Canvas tab (margin, rotation)

    var borderTab: some View {
        VStack(spacing: 12) {
            LabeledSlider(label: "Margin", value: $state.canvasMargin, range: -100...100, step: 1, format: "%.0f",
                          resetValue: 0)
            LabeledSlider(label: "Rotation", value: $state.canvasRotation, range: -15...15, step: 0.1, format: "%.1f°",
                          resetValue: 0)
        }
        .swipeNumbersToReset(canReset: state.canvasMargin != 0 || state.canvasRotation != 0) {
            state.canvasMargin = 0
            state.canvasRotation = 0
        }
    }

    // MARK: - Frames tab (adaptive frames + frame packs)

    var framesTab: some View {
        FramesPanel()
    }

    // MARK: - Overlay tab (dust, scratches, light leaks)

    var overlayTab: some View {
        OverlayPanel()
    }

    // MARK: - Effects tab (brightness, contrast, fade, glow, …)

    var effectsTab: some View {
        EffectsPanel()
    }
}

/// Sizes the panel's scroll view to its content's own height, up to `cap`,
/// in the same layout pass (no frame of the wrong size when a tab changes).
private struct CappedHeight: Layout {
    var cap: CGFloat

    var animatableData: CGFloat {
        get { cap.isFinite ? cap : 0 }
        set { if cap.isFinite { cap = newValue } }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        // A vertical scroll view's ideal height is its content's height.
        let natural = child.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: proposal.width ?? natural.width, height: min(natural.height, cap))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}
