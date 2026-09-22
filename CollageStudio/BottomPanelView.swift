import SwiftUI
#if canImport(PhotosUI)
import PhotosUI
#endif

/// The floating tab pill at the bottom of the phone layout: one glass
/// capsule, always visible while there are images, a tab per panel. Tapping
/// a tab raises the panel card above it; tapping the open tab again lowers
/// it. The active tab sits in a soft bubble that slides between tabs.
struct FloatingTabBar: View {
    @EnvironmentObject var state: CollageState
    /// True while the panel card is up: the pill drops its own glass and
    /// becomes the bottom row of the card, behind an inset separator.
    var merged = false
    @Namespace private var bubble

    static let tabs = ["Images", "Layout", "Canvas", "Frames", "Overlay", "Effects"]
    static let icons = ["photo.on.rectangle.angled", "square.grid.2x2", "rectangle.inset.filled",
                        "photo.artframe", "sparkles", "wand.and.stars"]
    /// Vertical room the pill takes at the bottom of the screen (pill +
    /// its margins) — what the panel card and the canvas leave free.
    static let zoneHeight: CGFloat = 80
    /// Extra room between the panel content and the tab row while the panel
    /// is open; the pill itself never moves.
    static let openLift: CGFloat = 0
    /// Corner radius of the pill, and of the card it merges into.
    static let cornerRadius: CGFloat = 24

    /// The chosen tab keeps its bubble even while its panel is lowered, so
    /// the pill always shows which tools are one tap away.
    private var activeTab: Int { state.selectedPanelTab }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Self.tabs.indices, id: \.self) { i in
                let active = activeTab == i
                Button {
                    select(i)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: Self.icons[i])
                            .font(.system(size: 19, weight: active ? .medium : .regular))
                            .frame(height: 24)
                        Text(Self.tabs[i])
                            .font(.system(size: 9.5, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.horizontal, 8)
                    .foregroundStyle(active ? Color.accentColor : Color.primary.opacity(0.72))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    // Selection bubble: a denser, matte piece of glass sitting
                    // in the pill, the icon and label in the accent color.
                    .background {
                        if active {
                            let shape = RoundedRectangle(cornerRadius: Self.cornerRadius - 5, style: .continuous)
                            shape
                                .fill(.regularMaterial)
                                .overlay(shape.fill(Color.primary.opacity(0.07)))
                                .overlay(shape.strokeBorder(Color.white.opacity(0.5), lineWidth: 0.8))
                                .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
                                .matchedGeometryEffect(id: "bubble", in: bubble)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .background {
            if !merged {
                let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.strokeBorder(Color.white.opacity(0.6), lineWidth: 0.8))
                    .shadow(color: .black.opacity(0.14), radius: 16, y: 6)
            }
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
        .animation(.easeInOut(duration: 0.25), value: merged)
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    private func select(_ i: Int) {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        state.closeRatio()
        if state.textEditTargetId != nil {
            // Any tab leaves text editing and shows that tab.
            state.endTextEditing()
            state.selectedPanelTab = i
        } else if state.selectedPanelTab == i && state.isPanelOpen {
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
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showOneOnOneConfirm = false
    @State private var showBurstConfirm = false
    @State private var showBurstAllConfirm = false
    @State private var showAllOnOneConfirm = false
    @State private var pagesContentHeight: CGFloat = 0

    private let card = RoundedRectangle(cornerRadius: FloatingTabBar.cornerRadius, style: .continuous)
    /// While up, the card's glass reaches down around the tab pill so the
    /// two read as one piece (see FloatingTabBar.merged).
    private var merged: Bool { state.isPanelOpen && state.panelDrag == 0 }

    var body: some View {
        VStack(spacing: 0) {
            // Grabber: a downward swipe on it collapses the panel (no
            // interactive follow — just closes on release, so no flicker).
            Capsule()
                .fill(Color.primary.opacity(0.22))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 2)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .panelChrome(state)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 12)
                        .onEnded { value in
                            if value.translation.height > 20 {
                                state.collapsePanel()
                            }
                        }
                )

            // Panel content — each tab is only as tall as its own content.
            Group {
                // Editing a text box takes over the panel until it's done.
                if let textId = state.textEditTargetId {
                    TextEditPanel(imageId: textId)
                } else {
                    switch state.selectedPanelTab {
                    case 0: imagesTab
                    case 1: layoutTab
                    case 2: borderTab
                    case 3: framesTab
                    case 4: overlayTab
                    default: effectsTab
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 6)
        }
        // Floating glass card. Fades while adjusting a slider so the collage
        // shows through; lives here so the drag offset moves it with the content.
        .background {
            card
                .fill(.ultraThinMaterial)
                .overlay(card.strokeBorder(Color.white.opacity(0.55), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.12), radius: 18, y: 6)
                .padding(.bottom, merged ? -(FloatingTabBar.zoneHeight - 8 + FloatingTabBar.openLift) : 0)
                .animation(.easeInOut(duration: 0.25), value: merged)
                .opacity(state.activeAdjustment == nil && !state.shuffleFocusActive ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: state.activeAdjustment)
        }
        // Report the card's height so it knows how far to slide to be fully
        // hidden: past the tab bar zone and the home-indicator area.
        .background(
            GeometryReader { g in
                Color.clear
                    .onAppear { state.panelHeight = g.size.height + FloatingTabBar.zoneHeight + 60 }
                    .onChange(of: g.size.height) { _, h in
                        state.panelHeight = h + FloatingTabBar.zoneHeight + 60
                    }
            }
        )
        .onChange(of: photoItems) { _, items in
            Task { await loadPhotos(items) }
        }
    }

    // MARK: - Images tab

    var imagesTab: some View {
        VStack(spacing: 10) {
            // Fixed button bar — does not scroll with the page list
            HStack(spacing: 8) {
                PhotosPicker(selection: $photoItems, maxSelectionCount: 30, matching: .images) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 17, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundColor(.white)
                        .background(Color.accentColor)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)

                // Adds a transparent placeholder — an intentional empty slot.
                Button { state.addEmptyImage() } label: {
                    Image(systemName: "rectangle.dashed.badge.record")
                        .font(.system(size: 17, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundColor(.white)
                        .background(Color.accentColor)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)

                // Adds an editable text box rendered as an image.
                Button { state.addTextImage() } label: {
                    Image(systemName: "character.textbox")
                        .font(.system(size: 17, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundColor(.white)
                        .background(Color.accentColor)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)

                ActionButton(label: "", sf: "doc.badge.plus") { state.addPage() }
                    .disabled(state.pages.count >= CollageState.maxPages)
                    .opacity(state.pages.count >= CollageState.maxPages ? 0.5 : 1)

                SpreadMenuButton(
                    onBurst: { showBurstConfirm = true },
                    onOnePerPage: { showOneOnOneConfirm = true },
                    onAllOnOne: { showAllOnOneConfirm = true },
                    onBurstAll: { showBurstAllConfirm = true })

                ActionButton(label: "", sf: "trash", fillWidth: false) { state.clear() }
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
                Text("This will put all images on a single page and delete the other pages, do you want to proceed?")
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
            LabeledSlider(label: "Columns", value: Binding(
                get: { Double(min(state.numCols, state.maxSelectableCols)) },
                set: { v in state.numCols = Int(v); state.rebuildLayout(resetGrows: true) }
            ), range: 1...Double(state.maxSelectableCols), step: 1, format: "%.0f", resetValue: 2)
                .disabled(state.maxSelectableCols <= 1)
                .opacity(state.maxSelectableCols <= 1 ? 0.4 : 1)

            LabeledSlider(label: "Spacing", value: $state.gap, range: 0...70, step: 1, format: "%.0f",
                          resetValue: 10, swatchColor: $state.backgroundColor)

            LabeledSlider(label: "Rounding", value: $state.cornerRadius, range: 0...100, step: 1, format: "%.0f",
                          resetValue: 20)
                // The chain sits in this row's empty swatch slot, visually
                // connecting the Background and Border color circles
                .overlay(alignment: .trailing) {
                    ColorLinkToggle().panelChrome(state)
                }

            BorderStyleRow()

            BorderPlacementRow()

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
                ActionButton(label: "Reset", sf: "arrow.counterclockwise", fillWidth: false) { state.resetStyle() }
                    .panelChrome(state)
            }
        }
    }

    // MARK: - Canvas tab (margin, rotation)

    var borderTab: some View {
        VStack(spacing: 12) {
            LabeledSlider(label: "Margin", value: $state.canvasMargin, range: -100...100, step: 1, format: "%.0f",
                          resetValue: 0)
            LabeledSlider(label: "Rotation", value: $state.canvasRotation, range: -60...60, step: 1, format: "%.0f°",
                          resetValue: 0)
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

    // MARK: - Effects tab (fade, halation, glow, B&W, …)

    var effectsTab: some View {
        EffectsPanel()
    }

    // MARK: - Load photos

    @MainActor
    func loadPhotos(_ items: [PhotosPickerItem]) async {
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
}

