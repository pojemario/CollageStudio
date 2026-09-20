import SwiftUI
#if canImport(PhotosUI)
import PhotosUI
#endif

struct BottomPanelView: View {
    @EnvironmentObject var state: CollageState
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showOneOnOneConfirm = false
    @State private var showBurstConfirm = false
    @State private var showBurstAllConfirm = false
    @State private var showAllOnOneConfirm = false
    @State private var pagesContentHeight: CGFloat = 0

    // Flat, edge-to-edge panel — no rounded corners.
    private let topCorners = Rectangle()

    let tabs = ["Images", "Layout", "Canvas"]
    let tabIcons = ["photo.badge.plus", "square.grid.2x2", "photo.artframe"]

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach(tabs.indices, id: \.self) { i in
                    Button {
                        if state.selectedPanelTab == i && state.isPanelOpen {
                            #if canImport(UIKit)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            withAnimation(.easeInOut(duration: 0.25)) { state.isPanelOpen = false }
                        } else {
                            state.selectedPanelTab = i
                            withAnimation(.easeInOut(duration: 0.25)) { state.isPanelOpen = true }
                        }
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: tabIcons[i])
                                .font(.system(size: 16))
                            Text(tabs[i])
                                .font(.system(size: 9))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .foregroundColor(state.selectedPanelTab == i && state.isPanelOpen
                                         ? .white : .white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                }
            }
            .panelChrome(state)
            .contentShape(Rectangle())
            // A downward swipe on the icon area collapses the panel (no
            // interactive follow — just closes on release, so no flicker).
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onEnded { value in
                        if value.translation.height > 20 {
                            state.collapsePanel()
                        }
                    }
            )

            Divider().opacity(0.4)
                .panelChrome(state)

            // Panel content — each tab is only as tall as its own content.
            Group {
                switch state.selectedPanelTab {
                case 0: imagesTab
                case 1: layoutTab
                default: borderTab
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        // Ride as low as possible — pushed a few points past the safe area
        // so the collapsed tab bar sits right at the very bottom edge.
        .padding(.bottom, -2)
        .clipShape(topCorners)
        // Glass sheet that dives out from the very bottom of the screen, edge
        // to edge (extending behind the home indicator). Fades while adjusting
        // a slider. Lives here so the drag offset moves it with the content.
        .background {
            topCorners
                .fill(.ultraThinMaterial)
                .overlay(topCorners.strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 12, y: -2)
                .opacity(state.activeAdjustment == nil && !state.shuffleFocusActive ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: state.activeAdjustment)
                .ignoresSafeArea(edges: .bottom)
        }
        // Report the panel's height so the sheet knows how far to slide when
        // fully hidden (plus a buffer for the home-indicator area).
        .background(
            GeometryReader { g in
                Color.clear
                    .onAppear { state.panelHeight = g.size.height + 44 }
                    .onChange(of: g.size.height) { _, h in state.panelHeight = h + 44 }
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

    // MARK: - Canvas tab (margin, rotation, rounding + decorative frame)

    var borderTab: some View {
        VStack(spacing: 12) {
            LabeledSlider(label: "Margin", value: $state.canvasMargin, range: -100...100, step: 1, format: "%.0f",
                          resetValue: 0)
            LabeledSlider(label: "Rotation", value: $state.canvasRotation, range: -60...60, step: 1, format: "%.0f°",
                          resetValue: 0)
            FramePickerRow()
                .panelChrome(state)
        }
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

