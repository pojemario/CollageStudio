import SwiftUI
import TipKit
#if canImport(PhotosUI)
import PhotosUI
#endif

/// The floating tab pill at the bottom of the phone layout: one glass
/// capsule, always visible while there are images, a tab per panel. Tapping
/// a tab raises the panel card above it (a tap never lowers it: a tap on
/// the canvas does). The active tab sits in a lens that slides between tabs; dragging
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
    /// A tap moving the lens to another tab: like the segmented switches
    /// (Filter | Effects | Edit), it lifts into clear glass and stretches
    /// while it travels, then settles back to the solid chip.
    @State private var gliding = false
    @State private var glideToken = 0

    static let tabs = ["Images", "Layout", "Frames", "Overlay", "Looks"]
    static let icons = ["photo.on.rectangle.angled", "square.grid.2x2",
                        "photo.artframe", "sparkles", "camera.filters"]
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
    static let cornerRadius: CGFloat = 18
    /// Inset of the tabs (and so the lens) from the pill's top and bottom.
    private static let rowInset: CGFloat = 5
    /// The selection lens follows the pill's corners: concentric, its
    /// radius the pill's less its inset.
    private static let lensRadius: CGFloat = cornerRadius - rowInset
    /// Horizontal travel before a touch becomes a scrub instead of a tap.
    private static let scrubThreshold: CGFloat = 8
    private static let rowSpace = "FloatingTabBar.row"
    private static let tabHeight: CGFloat = 50

    /// The chosen tab keeps its lens even while its panel is lowered, so
    /// the pill always shows which tools are one tap away.
    private var activeTab: Int { state.selectedPanelTab }
    private var scrubbing: Bool { scrubX != nil }
    /// A photo is selected (and no editor has the panel).
    private var photoTools: Bool {
        state.selectedImage != nil && state.textEditTargetId == nil && state.protrusionTargetId == nil
            && state.photoEditTargetId == nil
    }
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
        // A selected photo's tools stand in for the tabs.
        .opacity(photoTools ? 0 : 1)
        .offset(y: photoTools ? 12 : 0)
        .accessibilityHidden(photoTools)
        .overlay {
            if let image = state.selectedImage, photoTools {
                PhotoToolsRow(image: image)
                    // Its own color, filling the pill: photo mode, not the tabs.
                    .background {
                        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                            .fill(PhotoToolsRow.background)
                            .padding(.vertical, -Self.rowInset)
                            .padding(.horizontal, -10)
                    }
                    .transition(.offset(y: 12).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: photoTools)
        .padding(.vertical, Self.rowInset)
        .padding(.horizontal, 10)
        .contentShape(Rectangle())
        // (Off while the photo tools show: their buttons take the touches.)
        .gesture(scrubGesture, including: photoTools ? .subviews : .all)
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
        // The open tab went away (the page became a spread): show Layout,
        // where that's set.
        .onChange(of: isAvailable(activeTab)) { _, available in
            if !available { state.selectedPanelTab = 1 }
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
        let onChip = !scrubbing && !gliding && activeTab == i && state.panelTabShown
        let hovered = scrubbing && hoverTab == i
        return VStack(spacing: 3) {
            Image(systemName: Self.icons[i])
                .font(.system(size: 19, weight: onChip || hovered ? .medium : .regular))
                .frame(height: 24)
                // A dot when this tab's settings are changed on this page.
                .overlay(alignment: .topTrailing) {
                    if hasChanges(i) {
                        Circle()
                            .fill(onChip ? Color.white : Color.accentColor)
                            .frame(width: 6, height: 6)
                            .offset(x: 5, y: -1)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: hasChanges(i))
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
        // Not available here: hidden, its place kept so the tabs never shift.
        .opacity(isAvailable(i) ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: isAvailable(i))
        .accessibilityHidden(!isAvailable(i))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tab.\(Self.tabs[i])")
        // Bigger text on the phone (labels here stay small): a long press
        // shows the tab enlarged, as iOS's own tab bars do.
        .accessibilityShowsLargeContentViewer { Label(Self.tabs[i], systemImage: Self.icons[i]) }
        .accessibilityValue(hasChanges(i) ? "Changed" : "")
        .accessibilityAddTraits(activeTab == i && state.panelTabShown ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { if isOpen(i) { putAway() } else { select(i) } }
    }

    /// The selection lens: a solid accent chip at rest, so the active tab
    /// reads at a glance over any canvas; lifted, larger clear glass while
    /// scrubbing, tracking the finger.
    private var lens: some View {
        let shape = RoundedRectangle(cornerRadius: Self.lensRadius, style: .continuous)
        let center = scrubX.map { min(max($0, tabWidth / 2), rowWidth - tabWidth / 2) }
            ?? (CGFloat(activeTab) + 0.5) * tabWidth
        return ZStack {
            shape
                .fill(LinearGradient(colors: [Color.accentColor.opacity(0.85), Color.accentColor],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(shape.strokeBorder(Color.white.opacity(0.35), lineWidth: 0.8))
                .shadow(color: Color.accentColor.opacity(0.45), radius: 6, y: 2)
                .opacity(scrubbing || gliding || !state.panelTabShown ? 0 : 1)
            clearGlass(shape)
                .opacity(scrubbing || gliding ? 1 : 0)
        }
        .frame(width: tabWidth, height: Self.tabHeight)
        .scaleEffect(scrubbing ? CGSize(width: 1.22, height: 1.3)
                     : gliding ? CGSize(width: 1.3, height: 1.18) : CGSize(width: 1, height: 1))
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
                guard isAvailable(i) else { return }
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
                    TabBarTip().invalidate(reason: .actionPerformed)
                    // Let go over a hidden tab: the last one passed.
                    if let pick = isAvailable(i) ? i : hoverTab { select(pick) }
                    scrubX = nil
                    hoverTab = nil
                } else {
                    guard isAvailable(i) else { return }
                    if i != activeTab || !state.panelTabShown { glide() }
                    // A tap on the open tab puts it away (a scrub that ends
                    // on it doesn't).
                    if isOpen(i) { putAway() } else { select(i) }
                }
            }
    }

    private func glide() {
        glideToken &+= 1
        let token = glideToken
        withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) { gliding = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            guard token == glideToken else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { gliding = false }
        }
    }

    /// Whether the current page has settings changed in a tab (Images has none).
    private func hasChanges(_ i: Int) -> Bool {
        switch i {
        case 1: return state.hasStyleChanges || state.isRows || state.isStrip
            || state.canvasMargin != 0 || state.canvasRotation != 0
        case 2: return state.canvasFrame != nil
        case 3: return !state.overlayLayers.isEmpty
        case 4: return state.colorFilter != .none || state.hasEditChanges
        default: return false
        }
    }

    /// Whether a tab has anything to offer on this page: a spread page
    /// has no frames.
    private func isAvailable(_ i: Int) -> Bool {
        i != 2 || state.slides <= 1
    }

    private func tab(at x: CGFloat) -> Int {
        guard tabWidth > 0 else { return activeTab }
        return min(max(Int(x / tabWidth), 0), Self.tabs.count - 1)
    }

    /// The tab's panel is up, with no editor in it.
    private func isOpen(_ i: Int) -> Bool {
        i == activeTab && state.panelTabShown && state.isPanelOpen
            && state.textEditTargetId == nil && state.protrusionTargetId == nil && state.photoEditTargetId == nil
    }

    /// Second tap on the open tab: panel down, no tab chosen.
    private func putAway() {
        Diagnostics.log("tab \(Self.tabs[activeTab]) put away")
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        state.collapsePanel()
        withAnimation(.easeInOut(duration: 0.25)) { state.panelTabShown = false }
    }

    /// Opens a tab's panel; tapping it again puts it away (so does a
    /// double-tap on the panel's grabber, or a tap on the canvas).
    private func select(_ i: Int) {
        Diagnostics.log("tab \(Self.tabs[i]) (row \(Int(rowWidth))) · \(state.diagnosticsSummary)")
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
        state.closeRatio()
        // Nothing chosen yet (a saved collage just opened): open this tab.
        state.panelTabShown = true
        if state.textEditTargetId != nil || state.protrusionTargetId != nil || state.photoEditTargetId != nil {
            // Any tab leaves text / cutout / photo editing and shows that tab.
            state.endTextEditing()
            state.endProtrusionEditing()
            state.endPhotoEditing()
            state.selectImage(nil, keepTab: true)
            state.selectedPanelTab = i
        } else {
            state.selectedPanelTab = i
            withAnimation(.easeInOut(duration: 0.25)) { state.isPanelOpen = true }
        }
    }
}

/// The selected photo's tools, in the tab bar's place: Close, Cutout,
/// Replace, Move, Reset, Remove. Move swaps the row for the pages it can
/// go to.
struct PhotoToolsRow: View {
    /// The tab bar inverted, so photo mode is never mistaken for the tabs:
    /// light appearance (dark tabs on light glass) gets a solid charcoal
    /// pill with white tools, dark appearance a solid warm-white pill with
    /// black tools. Solid: nothing of the collage shows through it.
    static let background = adaptive(light: (0.16, 0.14, 0.13, 1), dark: (0.96, 0.94, 0.91, 1))
    /// The tools on it.
    static let foreground = adaptive(light: (1, 1, 1, 0.95), dark: (0.08, 0.07, 0.06, 0.95))
    /// The line setting Close apart.
    static let separator = adaptive(light: (1, 1, 1, 0.22), dark: (0, 0, 0, 0.18))
    /// Remove, in a red that reads on the pill.
    static let removeTint = adaptive(light: (1.0, 0.42, 0.4, 1), dark: (0.82, 0.13, 0.11, 1))

    private static func adaptive(light: (CGFloat, CGFloat, CGFloat, CGFloat),
                                 dark: (CGFloat, CGFloat, CGFloat, CGFloat)) -> Color {
        #if canImport(UIKit)
        Color(UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: c.3)
        })
        #else
        Color(red: light.0, green: light.1, blue: light.2, opacity: light.3)
        #endif
    }

    @EnvironmentObject var state: CollageState
    let image: CollageImage
    @State private var moving = false

    private static let height: CGFloat = 50

    private var movablePages: [Int] {
        let source = state.pageIndex(containing: image.id)
        return state.pages.indices.filter { pi in
            pi != source && state.pages[pi].images.count < CollageState.maxImagesPerPage
        }
    }
    private var canMove: Bool { !movablePages.isEmpty || state.canAddPost }

    var body: some View {
        Group {
            if moving { pages } else { tools }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: moving)
        .onChange(of: image.id) { _, _ in moving = false }
    }

    /// Every tool keeps its place; one that doesn't apply to this box (a
    /// text box can't be cut out, say) is hidden, so the others never move.
    private var tools: some View {
        HStack(spacing: 0) {
            tool("Close", sf: "xmark") { state.selectImage(nil) }
            // Sets Close apart from the photo's tools.
            Rectangle().fill(Self.separator).frame(width: 1, height: 30)
            tool("Cutout", sf: "person.crop.square", available: image.canProtrude) {
                state.selectImage(nil, keepTab: true)
                state.beginProtrusion(id: image.id)
            }
            tool("Replace", sf: "photo.on.rectangle.angled", available: !image.isText) {
                state.boxActionTargetId = image.id
                state.showReplacePicker = true
            }
            tool("Move", sf: "arrow.up.right.square", available: canMove) { moving = true }
            let isPhoto = !image.isText && !image.isPlaceholder
            tool("Reset", sf: "arrow.counterclockwise", available: isPhoto) {
                withAnimation(.easeInOut(duration: 0.2)) { state.resetTransform(id: image.id) }
            }
            tool("Edit", sf: "slider.horizontal.3", available: isPhoto) { state.beginPhotoEdit(id: image.id) }
            tool("Remove", sf: "trash", tint: Self.removeTint) {
                state.selectImage(nil)
                state.removeImage(id: image.id)
            }
        }
        .transition(.opacity)
    }

    /// Where the photo can go: each page with room, or a new one.
    private var pages: some View {
        HStack(spacing: 0) {
            tool("Back", sf: "chevron.left") { moving = false }
                .frame(width: 58)
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(movablePages, id: \.self) { pi in
                        tool("Page \(pi + 1)", sf: pi < 50 ? "\(pi + 1).square" : "square") {
                            moveTo { state.moveImage(id: image.id, toPage: pi) }
                        }
                        .frame(width: 62)
                    }
                    if state.canAddPost {
                        tool("New Page", sf: "plus.square.on.square") {
                            moveTo { state.moveImageToNewPage(id: image.id) }
                        }
                        .frame(width: 70)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
        .transition(.opacity)
    }

    private func moveTo(_ move: () -> Void) {
        moving = false
        state.selectImage(nil)
        move()
    }

    private func tool(_ title: String, sf: String, tint: Color = .primary, available: Bool = true,
                      action: @escaping () -> Void) -> some View {
        Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            action()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: sf)
                    .font(.system(size: 19))
                    .frame(height: 24)
                Text(title)
                    .font(.system(size: 9.5, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(tint == .primary ? Self.foreground : tint)
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityShowsLargeContentViewer { Label(title, systemImage: sf) }
        .opacity(available ? 1 : 0)
        .disabled(!available)
        .accessibilityHidden(!available)
    }
}

/// The panel card: the content of the selected tab on a floating glass
/// sheet that rises above the tab pill.
struct BottomPanelView: View {
    @EnvironmentObject var state: CollageState

    /// Natural height of the panel content, and how much of it shows.
    @State private var contentHeight: CGFloat = 0
    @State private var shownHeight: CGFloat = 0
    /// Content height while the grabber is being dragged (and while it
    /// settles after); nil otherwise.
    @State private var liveCap: CGFloat?
    @State private var dragStartHeight: CGFloat?
    @State private var cardHeight: CGFloat = 0
    /// Global bottom of the content area (fixed while the panel is resized).
    @State private var contentBottomY: CGFloat = 0
    /// All Pages' row: its height, the room above the button included.
    private static let actionRowTop: CGFloat = 8
    private static let actionRowHeight: CGFloat = 38
    /// Only while it would change something: another page differs from
    /// this one in what the tab sets.
    private var showsActionRow: Bool {
        guard let parts = allPagesParts else { return false }
        return state.otherPagesDiffer(in: parts)
    }

    /// A small capsule button in the grabber row.
    private func rowButton(_ title: String, icon: String, accessibility: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
                .contentShape(Rectangle().inset(by: -8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
    }

    /// What "All Pages" copies from this tab, when it shows (more than one
    /// page, a tab's own settings, no editor open).
    private var allPagesParts: Set<PageLookPart>? {
        guard state.pages.count > 1, state.textEditTargetId == nil, state.protrusionTargetId == nil,
              state.photoEditTargetId == nil, state.panelTabShown else { return nil }
        switch state.selectedPanelTab {
        case 1: return state.layoutPage == .arrange ? nil : [.layout, .background, .border, .canvas]
        case 2: return [.frame]
        case 3: return [.overlays]
        case 4: return [.filter, .edits]
        default: return nil
        }
    }

    /// The smallest the panel can be dragged to (about one row of content).
    private static let minHeight: CGFloat = 80
    /// Within this of the full height a released drag snaps to full.
    private static let fullSnap: CGFloat = 28

    /// Each tab (and the text / protrusion editors) keeps its own size; one
    /// not resized yet shows at full height.
    private var capKey: Int {
        if state.textEditTargetId != nil { return -1 }
        if state.protrusionTargetId != nil { return -2 }
        if state.photoEditTargetId != nil { return -3 }
        // Layout's and Looks' pages each keep their own size.
        if state.selectedPanelTab == 1 && state.layoutPage != .layout {
            return state.layoutPage == .border ? 11 : 12
        }
        if state.selectedPanelTab == 4 && state.looksPage != .filter {
            switch state.looksPage {
            case .edit: return 14
            case .detail: return 16
            default: return 15
            }
        }
        return state.selectedPanelTab
    }

    private let card = RoundedRectangle(cornerRadius: FloatingTabBar.cornerRadius, style: .continuous)
    /// While up, the card's glass reaches down around the tab pill so the
    /// two read as one piece (see FloatingTabBar.merged).
    private var merged: Bool { state.isPanelOpen && state.panelDrag == 0 }
    /// Shorter than its content: the content scrolls.
    private var scrolls: Bool { contentHeight > shownHeight + 1 }
    /// The tallest the content may show: the card's top stops just under
    /// the pager (or the toolbar). The grabber row takes the rest.
    private var maxShown: CGFloat {
        guard contentBottomY > 0, state.panelTopLimitY > 0 else { return .infinity }
        return max(contentBottomY - state.panelTopLimitY - Self.grabberHeight
                   - (showsActionRow ? Self.actionRowHeight : 0), Self.minHeight)
    }
    /// The panel at its full size: all of its content, if that fits.
    private var fullHeight: CGFloat { min(contentHeight, maxShown) }
    private static let grabberHeight: CGFloat = 15

    var body: some View {
        VStack(spacing: 0) {
            // Grabber: drag it to size the panel (it stays where it's left,
            // and the content scrolls when it doesn't all fit). It doesn't
            // close the panel on its own: a tap on the canvas does, and a
            // double-tap here puts it away with no tab selected.
            // Cut short (it can grow): inset like a slider's track, a hint
            // there's more. At full height: the plain gray bar.
            // Lit from the upper left (about 120°): the top-left inner edge
            // falls in shadow, the bottom-right one and the rim below catch
            // the light.
            Capsule()
                .fill(scrolls
                      ? AnyShapeStyle(Color.primary.opacity(0.2)
                            .shadow(.inner(color: .black.opacity(0.6), radius: 1.2, x: 0.8, y: 1.4))
                            .shadow(.inner(color: .white.opacity(0.35), radius: 0.8, x: -0.6, y: -1)))
                      : AnyShapeStyle(Color.primary.opacity(0.22)))
                .overlay {
                    if scrolls {
                        Capsule().strokeBorder(Color.black.opacity(0.22), lineWidth: 0.5)
                    }
                }
                .shadow(color: .white.opacity(scrolls ? 0.85 : 0), radius: 0.3, x: 0.6, y: 1)
                .frame(width: 36, height: scrolls ? 7 : 5)
                .animation(.easeInOut(duration: 0.2), value: scrolls)
                .padding(.top, 7)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                // A taller touch area, reaching over the content's top padding.
                .padding(.bottom, -6)
                .panelChrome(state)
                .gesture(resizeGesture)
                .simultaneousGesture(TapGesture(count: 2).onEnded {
                    Diagnostics.log("panel put away (grabber)")
                    state.collapsePanel()
                    withAnimation(.easeInOut(duration: 0.25)) { state.panelTabShown = false }
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                })
                .accessibilityHidden(true)
                .zIndex(1)

            // Under the grabber, lined up with the content's right edge:
            // All Pages (more than one page: this tab's settings onto every
            // page).
            if showsActionRow {
                HStack(spacing: 8) {
                    Spacer()
                    if showsActionRow, let parts = allPagesParts {
                        rowButton("All Pages", icon: "square.on.square",
                                  accessibility: "Apply \(FloatingTabBar.tabs[state.selectedPanelTab]) settings to all pages") {
                            let n = state.applyToAllPages(parts)
                            state.flashToast("Applied to all \(n + 1) pages", icon: "square.on.square")
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, Self.actionRowTop)
                .frame(height: Self.actionRowHeight)
                // Gone while one slider is being dragged (only it shows).
                .panelChrome(state)
                .allowsHitTesting(state.activeAdjustment == nil)
            }

            // Panel content — each tab is only as tall as its own content,
            // or as the size the panel was dragged to.
            CappedHeight(cap: min(liveCap ?? state.panelCaps[capKey] ?? .infinity, maxShown)) {
                ScrollView(.vertical) {
                    panelContent
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                }
                .scrollDisabled(!scrolls || state.activeAdjustment != nil || state.isMovingThumb)
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
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { y in
                // Only measured with the panel fully up and still: while it
                // slides, its own offset would feed into its height (and the
                // height into the offset).
                guard state.panelOffset == 0, !state.isPanelDragging, y.differs(from: contentBottomY) else { return }
                contentBottomY = y
            }
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
            let height = h + FloatingTabBar.zoneHeight + 60
            if !state.isPanelDragging, height.differs(from: state.panelHeight) {
                Diagnostics.count("panelHeight")
                state.panelHeight = height
            }
        }
    }

    @ViewBuilder
    private var panelContent: some View {
        Group {
            // Editing a text box takes over the panel until it's done.
            if let textId = state.textEditTargetId {
                TextEditPanel(imageId: textId)
            } else if let protrudeId = state.protrusionTargetId {
                // So does a photo's cutout (photo toolbar → Cutout).
                ProtrusionPanel(imageId: protrudeId)
            } else if state.photoEditTargetId != nil {
                // And one photo's own edits (photo toolbar → Edit).
                PhotoEditPanel()
            } else {
                switch state.selectedPanelTab {
                case 0: imagesTab
                case 1: LayoutPanel()
                case 2: framesTab
                case 3: overlayTab
                default: LooksPanel()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
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
                liveCap = min(h, fullHeight)
            }
            .onEnded { _ in
                let floor = min(Self.minHeight, contentHeight)
                let h = liveCap ?? shownHeight
                let key = capKey
                dragStartHeight = nil
                if h >= fullHeight - Self.fullSnap {
                    settle(to: fullHeight) { state.panelCaps[key] = nil }
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
                // Back to the Collages screen (the open one is saved).
                ToolbarTile(sf: "square.stack", title: "Collages", prominent: false) { state.goToCollages() }

                AddPageTile { state.addPage() }
                    .disabled(!state.canAddPost)
                    .opacity(!state.canAddPost ? 0.5 : 1)

                // Adds a transparent placeholder — an intentional empty slot.
                ToolbarTile(sf: "rectangle.dashed.badge.record", title: "Empty Box") { state.addEmptyImage() }

                // Adds an editable text box rendered as an image.
                ToolbarTile(sf: "character.textbox", title: "Text Box") { state.addTextImage() }
            }

            // The page list at its full height: the panel can grow up to the
            // pager to show it, and scrolls past that.
            PageGroupsView()
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

/// One photo's own edits: the Edit tab's controls, working on the selected
/// photo only. Done goes back to the photo's tools.
struct PhotoEditPanel: View {
    @EnvironmentObject var state: CollageState

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label("Edit Photo", systemImage: "slider.horizontal.3")
                    .font(.headline)
                Spacer()
                if let photo = state.photoEditTarget, !photo.edit.isIdentity {
                    // Back to the photo as it is, in one go (Undo restores).
                    Button("Reset") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            state.editEffects = [:]
                            state.editHSL = HSLAdjustments()
                            state.editCalibration = CameraCalibration()
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                }
                Button("Done") { state.endPhotoEditing() }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .panelChrome(state)
            EffectsPanel()
        }
        // The photo was deleted or moved to another page: nothing to edit.
        .onChange(of: state.photoEditTarget == nil, initial: true) { _, gone in
            if gone { state.endPhotoEditing() }
        }
    }
}
