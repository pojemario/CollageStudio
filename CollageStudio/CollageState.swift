import SwiftUI
import PhotosUI
import Combine
import os

@MainActor
class CollageState: ObservableObject {

    // MARK: - Pages
    static let maxImagesPerPage = 15
    static let maxPages = 20
    /// Posts across all pages (a spread page is several): a carousel takes
    /// at most 20.
    static let maxPosts = 20
    /// Room for one more post: a new page, or a page spread wider.
    var canAddPost: Bool { pictureCount < Self.maxPosts }

    @Published var pages: [CollagePage] = [CollagePage()]
    /// Edge the incoming page slides in from — set from the navigation
    /// direction so the canvas page transition matches finger movement.
    /// Published, and set a beat BEFORE the page changes (see goToPage), so
    /// the outgoing page is already carrying the right transition when it
    /// leaves — set together with the index it would slide the old way.
    @Published var pageSlideEdge: Edge = .trailing

    /// Navigates with a direction-correct slide.
    func goToPage(_ index: Int, slide: Int? = nil) {
        guard pages.indices.contains(index), index != currentPageIndex else { return }
        pageSlideEdge = index > currentPageIndex ? .trailing : .leading
        DispatchQueue.main.async { [self] in
            // The picture is picked together with the page, so the page
            // sliding out never first scrolls to it.
            // (Checked again: pages may have gone meanwhile.)
            guard pages.indices.contains(index) else { return }
            if let slide { pendingSlideFocus = slide }
            withAnimation(.easeInOut(duration: 0.3)) { currentPageIndex = index }
        }
    }

    @Published var currentPageIndex: Int = 0 {
        didSet {
            if currentPageIndex != oldValue, !isExporting { Diagnostics.log("page \(currentPageIndex + 1)") }
            pageSlideEdge = currentPageIndex > oldValue ? .trailing : .leading
            // Highlight maps belong to the previous page's picture
            if currentPageIndex != oldValue {
                effectMaps.clear()
                pruneGradedProxies()
                sharpGeneration.withLock { $0 += 1 }
            }
            // goToPicture picks the picture before the page changes.
            if currentPageIndex != oldValue && !isExporting { slideFocus = pendingSlideFocus ?? 0 }
            pendingSlideFocus = nil
            // Tracked box frames belong to the previous page's boxes — but
            // only drop them when a different page is actually shown. didSet
            // also runs when the index is re-assigned or the current page just
            // moves to another index (page reorder, deleting another page,
            // single-page export); its boxes then keep their identity and
            // frames, never re-report them, and an empty table would leave
            // drag-to-swap dead until some unrelated relayout.
            if currentPage.id != framesPageId {
                framesPageId = currentPage.id
                imageFrames.removeAll()
                emptySlotFrames.removeAll()
                // Frames reported mid-slide would stay off until a relayout.
                refreshTrackedGeometry(after: 0.45)
            }
            clearSwapDrag()
            // Each page has its own overlays: keep the panel on one of them.
            if let sel = selectedOverlayId, !overlayLayers.contains(where: { $0.id == sel }) {
                selectedOverlayId = overlayLayers.last?.id
            } else if selectedOverlayId == nil {
                selectedOverlayId = overlayLayers.last?.id
            }
        }
    }
    /// The page whose boxes `imageFrames` / `emptySlotFrames` describe.
    private var framesPageId: UUID?

    /// Bumped to make every box re-report its frame (boxes key their
    /// reporting on it). Used once animations settle, so a frame captured
    /// mid-animation can't leave drag-to-swap aiming at the wrong place.
    @Published private(set) var geometryEpoch = 0

    func refreshTrackedGeometry(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.geometryEpoch &+= 1
        }
    }

    var safePageIndex: Int {
        max(min(currentPageIndex, pages.count - 1), 0)
    }

    var currentPage: CollagePage {
        get { pages[safePageIndex] }
        set { pages[safePageIndex] = newValue }
    }

    // The canvas, gestures and layout engine all operate on the visible page
    // through these accessors.
    var images: [CollageImage] {
        get { currentPage.images }
        set { currentPage.images = newValue }
    }

    var order: [UUID] {
        get { currentPage.order }
        set { currentPage.order = newValue }
    }

    // MARK: - Canvas
    @Published var ratio: CanvasRatio = .square
    /// One picture of the collage's ratio. A page is one picture, or
    /// several side by side (a wide page, see PageStyle.slides).
    @Published var pictureSize: CGSize = CGSize(width: 1024, height: 1024)
    /// The current page's canvas: its pictures side by side.
    var canvasSize: CGSize { Self.stripSize(pictureSize, slides: slides) }
    /// How many pictures wide the current page is.
    var slides: Int { min(max(currentPage.style.slides, 1), Self.maxSlides) }
    static let maxSlides = 10
    /// The picture of a wide page the canvas is zoomed to, or nil for the
    /// whole page (only on screen; a single-picture page ignores it).
    @Published var slideFocus: Int? = 0
    /// The zoomed-to picture, kept within the page (nil: the whole page).
    var focusedSlide: Int? {
        guard slides > 1, let f = slideFocus else { return nil }
        return min(max(f, 0), slides - 1)
    }

    // MARK: Pictures (every page's, in order — what a post is made of)

    /// Pictures in the whole collage: one per page, more for wide pages.
    var pictureCount: Int { pages.reduce(0) { $0 + min(max($1.style.slides, 1), Self.maxSlides) } }
    /// Where each page's pictures start in that count.
    func firstPicture(ofPage index: Int) -> Int {
        pages.prefix(index).reduce(0) { $0 + min(max($1.style.slides, 1), Self.maxSlides) }
    }
    /// The picture on screen (the first one while a wide page is shown whole).
    var currentPicture: Int { firstPicture(ofPage: safePageIndex) + (focusedSlide ?? 0) }

    /// The picture goToPicture wants on the page it's moving to.
    private var pendingSlideFocus: Int?

    /// Shows picture `k`: its page, zoomed to it if the page is wide.
    func goToPicture(_ k: Int) {
        var first = 0
        for (i, page) in pages.enumerated() {
            let n = min(max(page.style.slides, 1), Self.maxSlides)
            if k < first + n {
                let slide = k - first
                if i == safePageIndex {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { slideFocus = slide }
                } else {
                    goToPage(i, slide: slide)
                }
                return
            }
            first += n
        }
    }

    /// The post one step back (-1) or on (+1) from what's shown; with a
    /// spread page shown whole, the neighbouring pages'.
    private func postTarget(_ dir: Int) -> Int {
        let first = firstPicture(ofPage: safePageIndex)
        if slides > 1 && focusedSlide == nil { return dir < 0 ? first - 1 : first + slides }
        return currentPicture + dir
    }

    func canStepPost(_ dir: Int) -> Bool {
        let k = postTarget(dir)
        return k >= 0 && k < pictureCount
    }

    /// Previous / next post, as the pager's arrows (and a swipe under the
    /// canvas) do. Moving to another page also lowers the bottom panel.
    func stepPost(_ dir: Int) {
        guard canStepPost(dir) else { return }
        let k = postTarget(dir)
        let page = pages.indices.last { firstPicture(ofPage: $0) <= k } ?? 0
        if page != safePageIndex { collapsePanel() }
        goToPicture(k)
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    @Published var customWidth: String = "1200"
    @Published var customHeight: String = "900"
    @Published var customUnit: CustomUnit = .px

    // MARK: - Layout (stored per page in PageStyle)
    var numCols: Int {
        get { currentPage.style.numCols }
        set { currentPage.style.numCols = newValue }
    }
    /// Lanes as rows (side-by-side boxes) instead of columns.
    var isRows: Bool {
        get { currentPage.style.isRows }
        set { currentPage.style.isRows = newValue }
    }
    /// The page as one row of photos, each at its own shape (see PageStyle).
    var isStrip: Bool { currentPage.style.isStrip }

    /// Lanes: columns, rows, or a strip.
    enum Lanes: Hashable { case columns, rows, strip }
    var lanes: Lanes { isStrip ? .strip : isRows ? .rows : .columns }

    func setLanes(_ l: Lanes) {
        guard l != lanes else { return }
        let wasStrip = isStrip
        currentPage.style.isStrip = l == .strip
        currentPage.style.isRows = l == .rows
        // In or out of a strip the columns change: lay them out again.
        if wasStrip || l == .strip { rebuildLayout(resetGrows: true) }
    }
    /// Highest column count that makes sense for the current page — one column
    /// per image, capped at 6. Drives the Columns slider's range; the slider is
    /// disabled entirely when this is 1 (0 or 1 images on the page).
    var maxSelectableCols: Int {
        max(1, min(6, images.count))
    }
    var gap: Double {
        get { currentPage.style.gap }
        set { currentPage.style.gap = newValue }
    }
    var cornerRadius: Double {
        get { currentPage.style.cornerRadius }
        set { currentPage.style.cornerRadius = newValue }
    }

    var layout: CollageLayout {
        get { currentPage.layout }
        set { currentPage.layout = newValue }
    }

    // MARK: - Colors (stored per page in PageStyle)
    var backgroundColor: Color {
        get { currentPage.style.backgroundColor }
        set {
            currentPage.style.backgroundColor = newValue
            syncLinkedBorderColor()
        }
    }
    /// True while a potentially slow operation is running (image import,
    /// export). Drives the logo shimmer "work in progress" indicator.
    @Published var isBusy: Bool = false
    /// True specifically while images are being loaded or exported — drives
    /// the gray canvas spinner (the shimmer uses isBusy for every action).
    @Published var isLoading: Bool = false
    /// Picked photos being read in: how many of how many.
    @Published var importProgress: ImportProgress?
    struct ImportProgress: Equatable { var done: Int; var total: Int }

    /// Label of the slider currently being dragged. While set, the panel
    /// fades everything except that slider so the canvas stays visible.
    @Published var activeAdjustment: String? = nil
    /// A thumbnail in the Images page list is being dragged to another page
    /// (the panel holds still meanwhile).
    @Published var isMovingThumb = false

    /// True right after Shuffle is pressed — the panel fades to just the
    /// Shuffle button so new layouts are visible; resets 2s after the last tap.
    @Published var shuffleFocusActive: Bool = false
    private var shuffleFocusToken = 0

    /// Whether a panel control (identified by `label`) should be visible given
    /// the current focus mode. During slider focus only the active slider
    /// shows; during shuffle focus only the Shuffle button shows.
    func chromeVisible(for label: String?) -> Bool {
        if let active = activeAdjustment { return label == active }
        if shuffleFocusActive { return label == "Shuffle" }
        return true
    }

    private func beginShuffleFocus() {
        // Hide instantly when Shuffle is pressed (no fade), even if the caller
        // is inside an animation transaction.
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) { shuffleFocusActive = true }
        shuffleFocusToken += 1
        let token = shuffleFocusToken
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if token == shuffleFocusToken {
                // …reveal the panel back with a quick fade-in.
                withAnimation(.easeInOut(duration: 0.24)) { shuffleFocusActive = false }
            }
        }
    }

    @Published var gapColor: Color = .white
    var borderColor: Color {
        get { currentPage.style.borderColor }
        set {
            currentPage.style.borderColor = newValue
            // Manually diverging the border color breaks the link
            if linkBorderToBackground, !isSyncingLinkedColor, newValue != backgroundColor {
                linkBorderToBackground = false
            }
        }
    }
    /// When true, the border color is chained to the background color:
    /// background is the primary, border follows it.
    var linkBorderToBackground: Bool {
        get { currentPage.style.linkBorderToBackground }
        set {
            currentPage.style.linkBorderToBackground = newValue
            if newValue { syncLinkedBorderColor() }
        }
    }
    private var isSyncingLinkedColor = false

    private func syncLinkedBorderColor() {
        guard linkBorderToBackground, borderColor != backgroundColor else { return }
        isSyncingLinkedColor = true
        borderColor = backgroundColor
        isSyncingLinkedColor = false
    }

    var borderThickness: Double {
        get { currentPage.style.borderThickness }
        set { currentPage.style.borderThickness = newValue }
    }
    var borderStyle: BorderStyle {
        get { currentPage.style.borderStyle }
        set { currentPage.style.borderStyle = newValue }
    }
    var borderPlacement: BorderPlacement {
        get { currentPage.style.borderPlacement }
        set { currentPage.style.borderPlacement = newValue }
    }

    /// The current page's style at the moment it was last applied to all
    /// pages — used to disable "Apply to All" until something changes.
    @Published var lastAppliedStyle: PageStyle? = nil

    /// True when there's more than one page and the current style differs from
    /// what was last applied (i.e. there's something new to propagate).
    var canApplyToAll: Bool {
        pages.count >= 2 && currentPage.style != lastAppliedStyle
    }

    /// Copies the current page's style — all options, including Columns —
    /// to every other page.
    func applyStyleToAllPages() {
        let source = currentPage.style
        for pi in pages.indices where pi != safePageIndex {
            // (Each page keeps its own width.)
            let slides = pages[pi].style.slides
            pages[pi].style = source
            pages[pi].style.slides = slides
            // A single-post page never takes a strip, even later on.
            pages[pi].style.isStrip = source.isStrip && slides > 1
            // Columns may have changed, so rebuild that page's layout
            pages[pi].layout.resetGrows()
            pages[pi].layout.rebuild(images: pages[pi].images,
                                     order: pages[pi].order,
                                     numCols: source.numCols, strip: pages[pi].style.isStrip)
        }
        lastAppliedStyle = source
    }

    // MARK: - Canvas margin & frame
    /// Extra inset (in canvas pixels) the user adds on top of the frame's
    /// built-in minimum margins. 0 means "just the frame's own margins".
    var canvasMargin: Double {
        get { currentPage.look.canvasMargin }
        set { currentPage.look.canvasMargin = newValue }
    }
    /// Rotation of the collage grid within the canvas, in degrees.
    var canvasRotation: Double {
        get { currentPage.look.canvasRotation }
        set { currentPage.look.canvasRotation = newValue }
    }
    /// The selected decorative frame set, or nil for no frame.
    var canvasFrame: CanvasFrameSet? {
        get { currentPage.look.canvasFrame }
        set { currentPage.look.canvasFrame = newValue }
    }

    /// Bundled frame sets with their per-ratio variants. Asset names encode
    /// margins and ratio — see CanvasFrameSet. The r1x1 variant doubles as
    /// a fallback for ratios without a dedicated PNG.
    static let availableFrames: [CanvasFrameSet] = [
        CanvasFrameSet(baseName: "Kodak", variantAssets: [
            "Kodak_m26262626_r1x1",
            "Kodak_m26262626_r4x5",
            "Kodak_m26262626_r9x16",
            "Kodak_m26262626_r16x9",
        ]),
        CanvasFrameSet(baseName: "Portra400", variantAssets: [
            "Portra400_m26262626_r1x1",
        ]),
        CanvasFrameSet(baseName: "Medium", variantAssets: [
            "Medium_m20262026_r1x1",
            "Medium_m26562656_r4x5",
            "Medium_m56265626_r5x4",
            "Medium_m10201020_r9x16",
        ]),
    ]

    /// Bundled frame packs — each drawn for a single format and used as is.
    /// Add a pack by dropping its PNGs into Assets.xcassets/FramePacks/ and
    /// listing them here.
    static let framePacks: [FramePack] = [
        FramePack(name: "Film Slim", ratio: .portrait916, assets: [
            "FilmSlim916_Thin_m14141414_r9x16",
            "FilmSlim916_Nicked_m15151515_r9x16",
            "FilmSlim916_Scuffed_m14141414_r9x16",
            "FilmSlim916_Uneven_m13161416_r9x16",
            "FilmSlim916_Corner_m15151515_r9x16",
            "FilmSlim916_Hairline_m14141414_r9x16",
        ]),
        FramePack(name: "Analog", ratio: .portrait916, assets: [
            "Analog916_Beach_m43434237_r9x16",
            "Analog916_Notch_m45454545_r9x16",
            "Analog916_Amber400_m61436143_r9x16",
            "Analog916_Sloppy_m58625862_r9x16",
            "Analog916_Pan100_m57415741_r9x16",
            "Analog916_Dust_m39393939_r9x16",
            "Analog916_Portra400_m61426142_r9x16",
            "Analog916_Portra160_m40614061_r9x16",
            "Analog916_HP5_m58415841_r9x16",
            "Analog916_Delta100_m56435643_r9x16",
        ]),
        FramePack(name: "Instant", ratio: .portrait45, assets: [
            "Polaroid45_Classic_m080084080104_r4x5",
            "Polaroid45_Cream_m080084080104_r4x5",
            "Polaroid45_Black_m080084080104_r4x5",
            "Polaroid45_Taped_m080084080104_r4x5",
            "Polaroid45_Blush_m080084080104_r4x5",
            "Polaroid45_Mint_m080084080104_r4x5",
        ]),
        FramePack(name: "Film", ratio: .portrait916, assets: [
            "Film916_Thin_m31313131_r9x16",
            "Film916_Nicked_m32323232_r9x16",
            "Film916_Scuffed_m33333333_r9x16",
            "Film916_Uneven_m30363236_r9x16",
            "Film916_Corner_m32323232_r9x16",
            "Film916_Hairline_m30303030_r9x16",
        ]),
    ]

    /// Applies a pack frame. The canvas keeps its ratio; the frame is laid
    /// over it in the frame's own proportions.
    func applyFrame(_ frame: CanvasFrameSet, from pack: FramePack) {
        canvasFrame = frame
    }

    /// Asset name of the frame variant to draw: the one made for the current
    /// ratio if there is one, else the set's first variant (drawn
    /// undistorted, covering the canvas).
    private func resolvedFrameAssetName() -> String? {
        // Frames fit one picture; a carousel strip shows none (the page
        // keeps its frame for when it's a single picture again).
        guard slides == 1, let set = canvasFrame else { return nil }
        let suffix = ratio.rawValue.replacingOccurrences(of: ":", with: "x")
        // Asked several times per canvas redraw: the asset lookups (which
        // UIKit doesn't cache when they miss) are done once per frame and
        // ratio.
        let key = set.id + "|" + suffix
        if let hit = Self.frameAssetNames[key] { return hit }
        let name: String?
        if let exact = set.assetName(ratioSuffix: suffix), PlatformImage.named(exact) != nil {
            name = exact
        } else {
            name = set.variantAssets.first { PlatformImage.named($0) != nil }
        }
        Self.frameAssetNames[key] = name
        return name
    }

    private static var frameAssetNames: [String: String?] = [:]

    /// Minimum content margins of the frame variant in use — margins can
    /// differ per ratio (zero without a frame).
    var frameBaseMargins: (left: CGFloat, top: CGFloat, right: CGFloat, bottom: CGFloat) {
        guard let name = resolvedFrameAssetName() else { return (0, 0, 0, 0) }
        return CanvasFrameSet.margins(fromAssetName: name)
    }

    /// Frame image for the current canvas ratio. Falls back to the square
    /// 1:1 variant when the exact ratio isn't bundled.
    func resolvedFrame() -> (image: PlatformImage, name: String)? {
        guard let name = resolvedFrameAssetName(),
              let image = PlatformImage.named(name) else { return nil }
        return (image, name)
    }

    // MARK: - Overlays (dust, scratches, light leaks, flares)

    /// Overlay layers on the current page, bottom to top.
    var overlayLayers: [OverlayLayer] {
        get { currentPage.look.overlayLayers }
        set { currentPage.look.overlayLayers = newValue }
    }
    /// Layer being edited in the Overlay panel.
    @Published var selectedOverlayId: UUID? = nil
    /// Every layer is a full-canvas bitmap, so keep the stack bounded.
    static let maxOverlayLayers = 8

    /// Bundled overlay packs. Add one by dropping its PNGs into
    /// Assets.xcassets/Overlays/ and listing them here.
    static let overlayPacks: [OverlayPack] = [
        OverlayPack(name: "Light Leaks", kind: .leak, assets: [
            "Leak916_Edge", "Leak916_Corner", "Leak916_Band",
            "Leak916_Burn", "Leak916_Magenta", "Leak916_Streaks",
            "Leak916_Blaze", "Leak916_Coral",
        ]),
        OverlayPack(name: "Flares", kind: .flare, assets: [
            "Flare916_Glow", "Flare916_Sun", "Flare916_Dusk",
            "Flare916_Haze", "Flare916_Orbs", "Flare916_Star",
            "Flare916_Ghosts", "Flare916_Streak", "Flare916_Ring",
        ]),
        OverlayPack(name: "Dust & Scratches", kind: .dust, assets: [
            "Dust916_Fine", "Dust916_Heavy", "Dust916_Hairs",
            "Dust916_Scratches", "Dust916_Grit", "Dust916_Worn",
        ]),
    ]

    /// A texture being tried out: drawn live on the canvas and adjustable
    /// like a layer, but not part of the stack (or the export) until it is
    /// committed.
    @Published var overlayPreview: OverlayLayer? = nil

    var canAddOverlay: Bool { overlayLayers.count < Self.maxOverlayLayers }

    /// Layers to draw under or over the frame, in stacking order. The preview
    /// sits on top of its group — exactly where it lands once added.
    /// The part of a canvas of `size` an overlay fills: its slide on a
    /// strip, else all of it.
    func overlayRegion(_ layer: OverlayLayer, in size: CGSize) -> CGRect {
        guard slides > 1, let s = layer.slide else { return CGRect(origin: .zero, size: size) }
        let w = size.width / CGFloat(slides)
        return CGRect(x: CGFloat(min(max(s, 0), slides - 1)) * w, y: 0, width: w, height: size.height)
    }

    func visibleOverlays(aboveFrame: Bool) -> [OverlayLayer] {
        var layers = overlayLayers.filter { $0.aboveFrame == aboveFrame }
        if let preview = overlayPreview, preview.aboveFrame == aboveFrame, !isExporting {
            layers.append(preview)
        }
        return layers
    }

    /// Tapping a texture adds it as a layer right away (and selects it for
    /// editing) — nothing is left pending, so nothing can be lost by
    /// leaving the tab.
    func addOverlayLayer(asset: String, kind: OverlayKind) {
        guard canAddOverlay else { return }
        overlayPreview = nil
        var layer = OverlayLayer(asset: asset, kind: kind)
        // On a strip it goes on the slide in view (all of it when they all are).
        layer.slide = slides > 1 ? focusedSlide : nil
        overlayLayers.append(layer)
        selectedOverlayId = layer.id
    }

    func cancelOverlayPreview() {
        overlayPreview = nil
    }

    // Overlay mode: the collage is frozen and canvas gestures move / scale /
    // rotate the edited overlay instead. On the phone it starts when the
    // Overlay tab is chosen and survives hiding the panel (touching the canvas
    // hides it at once for a clear view; an "OVERLAY" label by the panel
    // handle marks the mode) until another tab is picked. The always-visible
    // sidebar is only in the mode while a layer is edited.
    @Published var overlayTabMode = false
    @Published var overlaySidebarShowing = false

    var overlayModeActive: Bool {
        overlayTabMode || (overlaySidebarShowing && editedOverlayId != nil)
    }

    /// Hands the canvas back to the collage; an unconfirmed preview goes too.
    func exitOverlayMode() {
        overlayTabMode = false
        overlayPreview = nil
        overlayPanelReturn?.cancel()
    }

    // While an overlay is placed by finger the panel gets out of the way;
    // a second after the fingers lift it comes back.
    private var overlayPanelReturn: DispatchWorkItem?

    /// Safe to call on every gesture update.
    func beginOverlayGesture() {
        overlayPanelReturn?.cancel()
        overlayPanelReturn = nil
        if isPanelOpen { collapsePanel(animated: false) }
    }

    func endOverlayGesture() {
        overlayPanelReturn?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.overlayModeActive, !self.isPanelOpen, !self.chromeHidden else { return }
            withAnimation(.easeInOut(duration: 0.25)) { self.isPanelOpen = true }
        }
        overlayPanelReturn = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    /// What canvas gestures and the panel controls edit: the live preview,
    /// else the selected layer.
    var editedOverlayId: UUID? {
        overlayPreview?.id ?? overlayLayers.first { $0.id == selectedOverlayId }?.id
    }

    var editedOverlay: OverlayLayer? {
        overlayPreview ?? overlayLayers.first { $0.id == selectedOverlayId }
    }

    private func updateEditedOverlay(_ change: (inout OverlayLayer) -> Void) {
        if overlayPreview != nil {
            change(&overlayPreview!)
        } else if let idx = overlayLayers.firstIndex(where: { $0.id == selectedOverlayId }) {
            change(&overlayLayers[idx])
        }
    }

    /// Commits a finished canvas gesture to the edited overlay, clamped by
    /// OverlayLayer.applying. `translation` is in canvas pixels.
    func transformEditedOverlay(scaleBy: CGFloat = 1, rotateBy: CGFloat = 0, translation: CGSize = .zero) {
        updateEditedOverlay { layer in
            layer = layer.applying(scaleBy: scaleBy, rotateBy: rotateBy,
                                   translation: translation, canvasSize: overlayRegion(layer, in: canvasSize).size)
        }
    }

    /// Double-tap: back to the canvas-filling default placement.
    func resetEditedOverlayTransform() {
        updateEditedOverlay { layer in
            layer.scale = 1
            layer.rotation = 0
            layer.offset = .zero
        }
    }

    func removeOverlay(id: UUID) {
        guard let idx = overlayLayers.firstIndex(where: { $0.id == id }) else { return }
        overlayLayers.remove(at: idx)
        if selectedOverlayId == id {
            selectedOverlayId = overlayLayers.indices.contains(idx)
                ? overlayLayers[idx].id : overlayLayers.last?.id
        }
    }

    // MARK: - Effects (exposure, contrast, fade, glow, …)

    /// Intensity per effect on the current page, 0...100; absent or 0 means off.
    var effects: [CollageEffect: Double] {
        get { currentPage.look.effects }
        set {
            currentPage.look.effects = newValue
            dropGradesIfIdentity()
        }
    }

    /// Strength of an effect, 0...1.
    func effectAmount(_ effect: CollageEffect) -> Double {
        guard !compareOriginal else { return 0 }
        let r = effect.range
        let s = effect.span
        return min(max((effects[effect] ?? 0) / s, r.lowerBound / s), r.upperBound / s)
    }

    /// Whether any effect of the given group (Edit or Effects page) is on.
    func hasEffects(in group: [CollageEffect]) -> Bool {
        group.contains { (effects[$0] ?? 0) != 0 }
    }

    func resetEffects(in group: [CollageEffect]) {
        for effect in group { effects[effect] = nil }
    }

    /// Which effects a shuffle touches (all by default).
    @Published var effectShuffleOptions: Set<CollageEffect> = Set(CollageEffect.looks)

    /// Random tasteful amounts for the chosen effects; the rest are untouched.
    func shuffleEffects() {
        for effect in effectShuffleOptions {
            switch effect {
            case .temperature: effects[effect] = Double(Int.random(in: -25...25))
            case .tint:       effects[effect] = Double(Int.random(in: -15...15))
            case .vibrance, .saturation, .exposure, .highlights, .shadows, .whites, .blacks, .texture, .dehaze:
                break   // Basic corrections: not shuffled
            case .clarity:    effects[effect] = Double(Int.random(in: 0...30))
            case .sharpness:  effects[effect] = Double(Int.random(in: 0...30))
            case .contrast:   effects[effect] = Double(Int.random(in: -20...30))
            case .fade:       effects[effect] = Double(Int.random(in: 0...30))
            case .halation:   effects[effect] = Double(Int.random(in: 0...70))
            case .glow:       effects[effect] = Double(Int.random(in: 0...60))
            case .vignette:   effects[effect] = Double(Int.random(in: 10...80))
            case .grain:      effects[effect] = Double(Int.random(in: 0...70))
            }
        }
    }

    // MARK: - HSL

    /// Per-color hue / saturation / luminance of the current page.
    var hsl: HSLAdjustments {
        get { currentPage.look.hsl }
        set {
            currentPage.look.hsl = newValue
            dropGradesIfIdentity()
        }
    }

    func resetHSL() { hsl = HSLAdjustments() }

    // MARK: - Camera calibration

    /// Edit tab → CC, for the current page.
    var calibration: CameraCalibration {
        get { currentPage.look.calibration }
        set {
            currentPage.look.calibration = newValue
            dropGradesIfIdentity()
        }
    }

    // MARK: - Filter

    /// Preset look (Edit tab → Filter) of the current page.
    var colorFilter: ColorFilter {
        get { currentPage.look.colorFilter }
        set {
            currentPage.look.colorFilter = newValue
            dropGradesIfIdentity()
        }
    }
    /// Percent, 0...200 (100 = the filter as designed).
    var filterStrength: Double {
        get { currentPage.look.filterStrength }
        set {
            currentPage.look.filterStrength = newValue
            dropGradesIfIdentity()
        }
    }
    /// True while a filter tile is held: the pictures show without the
    /// filter (a before / after peek); everything else stays applied.
    @Published var filterBypass = false

    // MARK: - Per-picture grading (HSL, clarity, sharpness)

    /// What the pictures currently get graded with.
    var contentGrade: ContentGrade {
        guard !compareOriginal else { return ContentGrade() }
        var grade = fullGrade
        if filterBypass { grade.filter = .none }
        return grade
    }

    /// True while the compare button is held: the collage shows without any
    /// edits, effects or filter (overlays and the frame stay).
    @Published var compareOriginal = false

    /// Whether the pictures have any edit, effect or filter to compare against.
    /// Whether any Edit slider (effects, HSL, calibration) is changed.
    var hasEditChanges: Bool {
        hasEffects(in: CollageEffect.allCases) || !hsl.isIdentity || !calibration.isIdentity
    }

    var hasLookEdits: Bool {
        !fullGrade.isIdentity || CollageEffect.allCases.contains { (effects[$0] ?? 0) != 0 }
            || currentPage.images.contains { !$0.edit.isIdentity }
    }

    // MARK: - Editing one photo (photo toolbar → Edit)

    /// Whether this is not nil, the Edit panel works on this photo alone.
    @Published var photoEditTargetId: UUID? = nil

    /// The photo being edited, while it's on the page showing.
    var photoEditTarget: CollageImage? {
        photoEditTargetId.flatMap { id in images.first { $0.id == id } }
    }

    func beginPhotoEdit(id: UUID) {
        let img = images.first { $0.id == id }
        Diagnostics.log("photo edit · \(img.map { "\(Int($0.naturalSize.width))x\(Int($0.naturalSize.height)) proxy \(Int($0.proxy.size.width)) sharp \(sharpCopies[id].map { "\(Int($0.edge))" } ?? "-") page grade \(fullGrade.isIdentity ? "none" : "on")" } ?? "not on page")")
        closeRatio()
        textEditTargetId = nil
        protrusionTargetId = nil
        withAnimation(.easeInOut(duration: 0.25)) {
            photoEditTargetId = id
            isPanelOpen = true
        }
    }

    func endPhotoEditing() {
        guard photoEditTargetId != nil else { return }
        withAnimation(.easeInOut(duration: 0.2)) { photoEditTargetId = nil }
    }

    private func updatePhotoEdit(_ change: (inout PhotoEdit) -> Void) {
        guard let id = photoEditTargetId, let pi = pageIndex(containing: id),
              let idx = pages[pi].images.firstIndex(where: { $0.id == id }) else { return }
        var e = pages[pi].images[idx].edit
        change(&e)
        e.effects = e.effects.filter { $0.value != 0 }
        pages[pi].images[idx].edit = e
    }

    /// What the Edit panel's sliders show and change: the photo being
    /// edited, else the page.
    var editEffects: [CollageEffect: Double] {
        get { photoEditTarget?.edit.effects ?? effects }
        set { if photoEditTargetId != nil { updatePhotoEdit { $0.effects = newValue } } else { effects = newValue } }
    }
    var editHSL: HSLAdjustments {
        get { photoEditTarget?.edit.hsl ?? hsl }
        set { if photoEditTargetId != nil { updatePhotoEdit { $0.hsl = newValue } } else { hsl = newValue } }
    }
    var editCalibration: CameraCalibration {
        get { photoEditTarget?.edit.calibration ?? calibration }
        set { if photoEditTargetId != nil { updatePhotoEdit { $0.calibration = newValue } } else { calibration = newValue } }
    }
    func editHasEffects(in group: [CollageEffect]) -> Bool { group.contains { (editEffects[$0] ?? 0) != 0 } }
    func editResetEffects(in group: [CollageEffect]) {
        var e = editEffects
        for effect in group { e[effect] = nil }
        editEffects = e
    }

    /// The grade with the filter, even while it's being bypassed.
    private var fullGrade: ContentGrade {
        Self.grade(effects: effects, hsl: hsl, calibration: calibration,
                   filter: colorFilter, filterStrength: filterStrength)
    }

    struct Graded {
        let source: PlatformImage
        let grade: ContentGrade
        let image: PlatformImage
    }

    /// Canvas proxies graded off the main thread, by image id — the two
    /// most recent grades each, so flipping between with / without the
    /// filter (holding a filter tile) is instant. While a slider moves, a
    /// box keeps showing its last grade until the next one lands.
    @Published private(set) var gradedProxies: [UUID: [Graded]] = [:]
    /// The grade underway per picture, by a token: a retry gets a new one,
    /// so the lost grade finishing late can't clear the retry's.
    private var gradeInFlight: [UUID: UUID] = [:]
    private var gradeStarted: [UUID: Date] = [:]
    /// Grades finished in the last moment, shown together (one canvas
    /// update) instead of picture by picture.
    private var gradesToShow: [UUID: Graded] = [:]
    private var gradeFlushScheduled = false
    /// Full-resolution grades for the export in progress (made synchronously
    /// while it renders; dropped when it ends).
    private var gradeExportCache: [UUID: Graded] = [:]
    /// The export in progress: each photo scaled to the pixels it fills at
    /// the export size (see prepareExportPage), drawn instead of the
    /// original.
    private var exportSources: [UUID: PlatformImage] = [:]

    func dropGradesIfIdentity() {
        if !needsGrading, !gradedProxies.isEmpty { gradedProxies = [:] }
    }

    /// Whether any picture on the page gets graded: page edits, or a
    /// photo with edits of its own.
    var needsGrading: Bool {
        !fullGrade.isIdentity || currentPage.images.contains { !$0.edit.isIdentity }
    }

    /// The grade a picture is drawn with: the page's, with the photo's own
    /// edits in front (none while comparing with the original).
    func grade(for img: CollageImage) -> ContentGrade {
        Self.merge(contentGrade, img.edit, comparing: compareOriginal)
    }

    nonisolated static func merge(_ page: ContentGrade, _ edit: PhotoEdit, comparing: Bool = false) -> ContentGrade {
        guard !comparing else { return ContentGrade() }
        guard !edit.isIdentity else { return page }
        var g = page
        g.photo = edit.grade
        // Detail: the photo's adds to the page's.
        g.clarity = min(max(g.clarity + edit.amount(.clarity), -1), 1)
        g.sharpness = min(max(g.sharpness + edit.amount(.sharpness), 0), 1)
        g.tone.texture = min(max(g.tone.texture + edit.amount(.texture), -1), 1)
        g.tone.dehaze = min(max(g.tone.dehaze + edit.amount(.dehaze), -1), 1)
        return g
    }

    /// The picture a box should draw: its proxy (or the original while
    /// exporting) with the current grade applied.
    func gradedDisplayImage(for img: CollageImage) -> PlatformImage {
        let source = renderFullResolution ? (exportSources[img.id] ?? img.image) : img.proxy
        let grade = grade(for: img)
        // Settled on screen: the sharp copy (see refreshSharpCopies).
        if !isRenderingOffscreen, grade.isIdentity,
           let s = sharpCopies[img.id], s.source === img.original { return s.image }
        guard !grade.isIdentity, !img.isPlaceholder else { return source }
        if renderFullResolution {
            if let g = gradeExportCache[img.id], g.source === source, g.grade == grade { return g.image }
            let graded = ContentGrader.apply(grade, to: source)
            gradeExportCache[img.id] = Graded(source: source, grade: grade, image: graded)
            return graded
        }
        // On screen and settled: the sharp copy, when it has this grade.
        if !isRenderingOffscreen, let s = sharpCopies[img.id], s.source === img.original,
           let g = s.graded, g.grade == grade { return g.image }
        let cached = (gradedProxies[img.id] ?? []).filter { $0.source === source }
        if let exact = cached.first(where: { $0.grade == grade }) { return exact.image }
        // Still grading (a slider is moving): keep showing the nearest
        // previous step of the same look — the one with the same filter
        // state, never the with / without-filter twin kept for the
        // before / after peek, which made sliders flicker.
        if let sameLook = cached.last(where: { $0.grade.filter == grade.filter }) { return sameLook.image }
        return cached.last?.image ?? source
    }

    /// Drops graded proxies of pictures not on the current page or its
    /// neighbours: paging through a graded collage otherwise keeps two
    /// graded copies of every photo it passed.
    func pruneGradedProxies() {
        let near = Set(pages.indices.filter { abs($0 - safePageIndex) <= 1 }
            .flatMap { pages[$0].images.map(\.id) })
        guard gradedProxies.keys.contains(where: { !near.contains($0) }) else { return }
        gradedProxies = gradedProxies.filter { near.contains($0.key) }
    }

    /// Low on memory: everything that can be made again goes — sharp
    /// copies, other pages' graded proxies, the cutout caches — and the
    /// undo history keeps only its last steps.
    func freeMemory() {
        Diagnostics.log("memory warning: caches dropped")
        sharpCopies = [:]
        let here = Set(currentPage.images.map(\.id))
        gradedProxies = gradedProxies.filter { here.contains($0.key) }
        subjectMasks = [:]
        mergedShapes = [:]
        instanceOutlines = [:]
        dilatedMasks = [:]
        subjectOutlines = [:]
        trimHistory(keeping: 5)
        ProjectThumbCache.images = [:]
    }

    /// Grades a box's proxy for the current settings unless that's already
    /// done or underway; a grade that finishes stale immediately catches up.
    /// With a filter on, the same picture without it is prepared next, so a
    /// before / after peek never waits.
    func gradeIfNeeded(_ img: CollageImage) {
        var grades = [grade(for: img)]
        // The peek's twin is prepared only when no slider is moving, so a
        // drag gets all the grading time.
        if fullGrade.hasFilter, activeAdjustment == nil {
            let full = Self.merge(fullGrade, img.edit)
            var without = full
            without.filter = .none
            grades.append(filterBypass ? full : without)
        }
        let source = img.proxy, id = img.id
        guard !img.isPlaceholder else { return }
        if gradeInFlight[id] != nil {
            // A grade takes well under a second; one still out after a few
            // is lost (logged, to find out why): let a new one start.
            guard let started = gradeStarted[id], Date().timeIntervalSince(started) > 4 else { return }
            Diagnostics.log("grade stuck \(String(format: "%.0f", Date().timeIntervalSince(started)))s, retrying")
            gradeInFlight[id] = nil
        }
        let cached = (gradedProxies[id] ?? []).filter { $0.source === source }
        guard let grade = grades.first(where: { g in
            !g.isIdentity && !cached.contains { $0.grade == g }
        }) else { return }
        let token = UUID()
        gradeInFlight[id] = token
        gradeStarted[id] = Date()
        let photoEdit = grade.photo != nil
        Task.detached(priority: .userInitiated) {
            let graded = ContentGrader.apply(grade, to: source)
            let unchanged = graded === source
            await MainActor.run {
                if self.gradeInFlight[id] == token {
                    self.gradeInFlight[id] = nil
                    self.gradeStarted[id] = nil
                }
                // Diagnostics: a photo's own edit that came back untouched.
                if photoEdit, unchanged { Diagnostics.log("photo grade failed (picture unchanged)") }
                guard self.needsGrading else {
                    if photoEdit { Diagnostics.log("photo grade dropped (no grading needed)") }
                    return
                }
                self.gradesToShow[id] = Graded(source: source, grade: grade, image: graded)
                self.scheduleGradeFlush()
            }
        }
    }

    /// Shows the grades that just finished all at once, then lets any
    /// picture whose grade went stale meanwhile catch up.
    private func scheduleGradeFlush() {
        guard !gradeFlushScheduled else { return }
        gradeFlushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            guard let self else { return }
            self.gradeFlushScheduled = false
            let done = self.gradesToShow
            self.gradesToShow = [:]
            guard self.needsGrading, !done.isEmpty else { return }
            var all = self.gradedProxies
            for (id, g) in done {
                var list = (all[id] ?? []).filter { $0.source === g.source && $0.grade != g.grade }
                list.append(g)
                all[id] = Array(list.suffix(2))
            }
            self.gradedProxies = all
            self.gradeFlushCount += 1
            for img in self.currentPage.images where done[img.id] != nil { self.gradeIfNeeded(img) }
        }
    }

    // MARK: Sharp copies
    // The 800 px proxy keeps editing fast, but a photo filling most of the
    // canvas is shown bigger than that and looks soft. Once nothing has
    // changed for a moment, every box whose photo is drawn bigger than its
    // proxy gets a copy made from the original at the size it's actually
    // shown (graded too); it's drawn until the next change of grade, while
    // the proxy keeps everything that moves fast.

    struct Sharp {
        /// The original it was made from (a replaced photo drops it).
        let source: OriginalPicture
        let edge: CGFloat
        let image: PlatformImage
        var graded: Graded? = nil
    }

    /// Long-edge cap for a sharp copy; a phone screen is ~1300 px across,
    /// so a pinched-in photo still has room.
    static let sharpMaxEdge: CGFloat = 2560
    /// Total pixels kept in sharp copies, graded copies included (a graded
    /// photo counts twice): ~100 MB at most.
    static let sharpPixelBudget: CGFloat = 24_000_000
    /// Bumped on a page change: sharp jobs still queued for the page left
    /// behind stop before decoding anything.
    nonisolated private let sharpGeneration = OSAllocatedUnfairLock(initialState: 0)

    @Published private(set) var sharpCopies: [UUID: Sharp] = [:]
    /// One copy at a time, off the shared task pool.
    nonisolated static let sharpQueue = DispatchQueue(label: "sharp", qos: .utility)
    private var sharpInFlight: Set<UUID> = []
    private var sharpRefresh: AnyCancellable?
    private var memoryWarning: AnyCancellable?

    private func observeSharpness() {
        sharpRefresh = objectWillChange
            .debounce(for: .milliseconds(700), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshSharpCopies() }
            }
        #if canImport(UIKit)
        memoryWarning = NotificationCenter.default
            .publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.freeMemory() }
            }
        #endif
    }

    /// The long edge, in pixels, a box's photo is drawn at on screen
    /// (rounded up to 256s, so small box changes don't remake it); nil when
    /// the proxy is enough.
    #if canImport(UIKit)
    /// The screen's scale (looked up once).
    private static let screenScale: CGFloat = UIApplication.shared.connectedScenes
        .compactMap { ($0 as? UIWindowScene)?.screen.scale }.first ?? 3
    #endif

    private func sharpEdge(for img: CollageImage) -> CGFloat? {
        guard !img.isPlaceholder,
              let placement = ImagePlacement.compute(natural: img.naturalSize, boxSize: img.lastBoxSize,
                                                     zoom: img.zoom, rotation: img.rotation, pan: .zero)
        else { return nil }
        #if canImport(UIKit)
        let screenScale = Self.screenScale
        #else
        let screenScale: CGFloat = 2
        #endif
        let shown = max(placement.size.width, placement.size.height) * max(screenScale, 1)
        let original = max(img.naturalSize.width, img.naturalSize.height)
        let edge = min((shown / 256).rounded(.up) * 256, Self.sharpMaxEdge, original)
        return edge > CollageImage.proxyLongEdge * 1.15 ? edge : nil
    }

    /// Makes (and grades) the sharp copies the current page needs, biggest
    /// first within the budget, and lets go of the rest.
    func refreshSharpCopies() {
        guard !isRenderingOffscreen, !isCanvasZooming, imageZoomingId == nil,
              activeAdjustment == nil else { return }
        let images = currentPage.images
        var wanted: [UUID: CGFloat] = [:]
        var budget = Self.sharpPixelBudget
        let needs = images.compactMap { img in sharpEdge(for: img).map { (img, $0) } }
            .sorted { $0.1 > $1.1 }
        for (img, edge) in needs {
            let aspect = min(img.naturalSize.width, img.naturalSize.height) / max(img.naturalSize.width, img.naturalSize.height)
            let pixels = edge * edge * aspect * (grade(for: img).isIdentity ? 1 : 2)
            guard pixels <= budget else { continue }
            budget -= pixels
            wanted[img.id] = edge
        }
        // Let go of copies no longer needed (another page, smaller box,
        // replaced photo).
        let keep = sharpCopies.filter { id, s in
            wanted[id] == s.edge && images.contains { $0.id == id && $0.original === s.source }
        }
        if keep.count != sharpCopies.count { sharpCopies = keep }

        let generation = sharpGeneration.withLock { $0 }
        let current = { [sharpGeneration] in sharpGeneration.withLock { $0 } == generation }
        for img in images {
            guard let edge = wanted[img.id], !sharpInFlight.contains(img.id) else { continue }
            let grade = grade(for: img)
            if let s = sharpCopies[img.id] {
                // Made already: grade it for the current settings.
                guard !grade.isIdentity, s.graded?.grade != grade else { continue }
                let id = img.id, base = s.image
                sharpInFlight.insert(id)
                Self.sharpQueue.async {
                    guard current() else {
                        DispatchQueue.main.async { self.sharpInFlight.remove(id) }
                        return
                    }
                    let graded = ContentGrader.apply(grade, to: base)
                    if graded === base { Diagnostics.log("sharp grade failed (picture unchanged)") }
                    DispatchQueue.main.async {
                        self.sharpInFlight.remove(id)
                        guard var cur = self.sharpCopies[id], cur.image === base else { return }
                        cur.graded = Graded(source: base, grade: grade, image: graded)
                        self.sharpCopies[id] = cur
                    }
                }
            } else {
                let id = img.id, original = img.original
                sharpInFlight.insert(id)
                Self.sharpQueue.async {
                    guard current() else {
                        DispatchQueue.main.async { self.sharpInFlight.remove(id) }
                        return
                    }
                    // Decoded straight at its size from the compressed original.
                    let sharp = autoreleasepool { original.scaled(maxEdge: edge) }
                    let graded = grade.isIdentity ? nil
                        : Graded(source: sharp, grade: grade, image: ContentGrader.apply(grade, to: sharp))
                    DispatchQueue.main.async {
                        self.sharpInFlight.remove(id)
                        guard self.currentPage.images.contains(where: { $0.id == id && $0.original === original })
                        else { return }
                        Diagnostics.log("sharp copy \(Int(edge)) px")
                        self.sharpCopies[id] = Sharp(source: original, edge: edge, image: sharp, graded: graded)
                    }
                }
            }
        }
    }

    /// Glow and halation are light spilling out of the highlights, so they
    /// need the rendered collage as input: a small snapshot of the current
    /// page is turned into blurred highlight maps that the canvas screens
    /// back on at the effect's intensity. Separate object, so publishing new
    /// maps doesn't re-trigger the refresh below.
    let effectMaps = EffectMaps()
    /// True while that snapshot renders: the canvas then draws the bare
    /// collage — no effects, overlays or frame.
    private(set) var isRenderingEffectSource = false
    /// True while any offscreen render runs (effect snapshot or export):
    /// boxes drawn there must not report their geometry as the on-screen one.
    var isRenderingOffscreen: Bool { isRenderingEffectSource || renderFullResolution || isRenderingThumbnail }
    private var effectMapRefresh: AnyCancellable?
    /// What the last highlight-map snapshot showed.
    private var lastEffectSource: EffectSourceKey?
    /// Bumped whenever graded pictures land (the snapshot shows them).
    private var gradeFlushCount = 0

    private struct EffectSourceKey {
        let page: CollagePage
        let grade: ContentGrade
        let canvas: CGSize
        let grades: Int
        let glow: Bool
        let halation: Bool

        func same(as o: EffectSourceKey) -> Bool {
            page.sameContent(as: o.page) && grade == o.grade && canvas == o.canvas
                && grades == o.grades && glow == o.glow && halation == o.halation
        }
    }

    /// Re-derives the maps shortly after anything settles; cheap no-op while
    /// neither effect is on.
    private func observeEffectSources() {
        effectMapRefresh = objectWillChange
            // Changes published by the snapshot render itself (geometry
            // bookkeeping) must not schedule another snapshot.
            .filter { [weak self] _ in
                !MainActor.assumeIsolated { self?.isRenderingEffectSource ?? false }
            }
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshEffectMaps() }
            }
    }

    /// `force` is for export, which needs fresh maps for the page it is
    /// about to render instead of waiting for the debounce.
    func refreshEffectMaps(force: Bool = false) {
        let glow = effectAmount(.glow) > 0, halation = effectAmount(.halation) > 0
        guard glow || halation, !currentPage.images.isEmpty else {
            effectMaps.clear()
            lastEffectSource = nil
            return
        }
        guard force || !isExporting else { return }
        // Not while a slider moves (its end publishes again), and not when
        // nothing the snapshot shows changed (a panel drag, a frame report).
        let key = EffectSourceKey(page: currentPage, grade: contentGrade, canvas: canvasSize,
                                  grades: gradeFlushCount, glow: glow, halation: halation)
        if !force {
            guard activeAdjustment == nil else { return }
            if let last = lastEffectSource, last.same(as: key) { return }
        }
        lastEffectSource = key

        isRenderingEffectSource = true
        defer { isRenderingEffectSource = false }
        let source = CollageGridView_Grid(scale: 1.0)
            .frame(width: canvasSize.width, height: canvasSize.height)
            .environmentObject(self)
        let renderer = ImageRenderer(content: source)
        renderer.proposedSize = ProposedViewSize(canvasSize)
        // The maps are heavily blurred — half resolution is plenty.
        renderer.scale = 0.5
        guard let snapshot = renderer.cgImage else { return }
        effectMaps.update(from: snapshot, glow: glow, halation: halation, slides: slides, sync: force)
    }

    // MARK: - Drag to swap
    @Published var swapArmedId: UUID? = nil
    @Published var draggingId: UUID? = nil
    @Published var dropTargetId: UUID? = nil
    /// Empty column currently hovered during a swap drag.
    @Published var dropTargetEmptyCol: Int? = nil
    /// Gap (splitter) currently hovered during a drag: dropping there inserts
    /// the image between its neighbours instead of swapping.
    @Published var dropInsertTarget: InsertTarget? = nil

    struct InsertTarget: Equatable {
        /// Column index and position in it (before the dragged image is
        /// taken out), plus the hover zone in "collageCanvas" space.
        let column: Int
        let index: Int
        let frame: CGRect
    }
    /// The dragged photo's offset. Kept in its own small object: published
    /// here, every drag frame redrew everything watching the collage.
    let swapDrag = SwapDragOffset()
    var dragOffset: CGSize {
        get { swapDrag.value }
        set { if swapDrag.value != newValue { swapDrag.value = newValue } }
    }
    var imageFrames: [UUID: CGRect] = [:]
    /// Frames of empty placeholder boxes on the current page, by column index.
    var emptySlotFrames: [Int: CGRect] = [:]

    // MARK: - Gesture coordination
    @Published var isCanvasZooming: Bool = false
    @Published var imageZoomingId: UUID? = nil

    // MARK: - Bottom panel visibility (iPhone)
    /// Starts collapsed so the first-run screen is just the canvas with the
    /// big "add images" button; opens automatically once images arrive.
    @Published var isPanelOpen: Bool = false

    // MARK: Interactive bottom-sheet drag
    /// Measured full height of the panel (incl. a buffer for the safe area),
    /// used as the fully-hidden offset.
    @Published var panelHeight: CGFloat = 320
    /// Full screen: the floating tab bar (and panel) are out of the way.
    @Published var chromeHidden: Bool = false
    /// Full screen: the toolbar and status bar are gone too, leaving only
    /// the collage. Always set together with chromeHidden.
    @Published var toolbarHidden: Bool = false

    /// Only the collage on screen: no status bar, toolbar, tab bar or
    /// panel, and nothing selected.
    func enterFullScreen() {
        closeRatio()
        if selectedImageId != nil { selectImage(nil) }
        withAnimation(.easeInOut(duration: 0.25)) {
            collapsePanel()
            chromeHidden = true
            toolbarHidden = true
        }
    }

    func exitFullScreen() {
        withAnimation(.easeInOut(duration: 0.25)) {
            toolbarHidden = false
            chromeHidden = false
        }
    }
    /// Top edge of the open panel card in global coordinates (0 while
    /// closed) — how much of the screen bottom the panel (and the keyboard
    /// pushing it up) covers, for keeping an edited text box in view.
    @Published var panelTopGlobalY: CGFloat = 0
    /// Highest the panel card's top may reach (global y): just under the
    /// pager, or under the toolbar when there's a single page.
    @Published var panelTopLimitY: CGFloat = 0
    /// Where on screen the canvas can be seen (global), and the controls
    /// floating over it (pager, compare button) — a text box's edit button
    /// moves to a corner none of them cover.
    @Published var canvasVisibleRect: CGRect = .zero
    @Published var pagerFrame: CGRect = .zero
    /// The phone toolbar's Undo button, for the Redo bubble below it.
    @Published var undoButtonFrame: CGRect = .zero
    /// The round buttons right of the pager (compare, spread zoom).
    @Published var compareButtonFrame: CGRect = .zero

    /// The part of the screen where a control on the collage can be seen
    /// and tapped: the canvas area above the open panel.
    var canvasClearRect: CGRect {
        var r = canvasVisibleRect
        if isPanelOpen, panelTopGlobalY > r.minY, panelTopGlobalY < r.maxY {
            r.size.height = panelTopGlobalY - r.minY
        }
        return r
    }
    var canvasObstacles: [CGRect] {
        [pagerFrame, compareButtonFrame].filter { !$0.isEmpty }
    }
    /// Live drag translation while the user is pulling the panel (+ = down).
    @Published var panelDrag: CGFloat = 0
    /// True while the panel's grabber is being dragged.
    @Published var isPanelDragging: Bool = false
    /// The panel content height the user dragged each tab's panel to
    /// (missing = full height); taller content scrolls.
    @Published var panelCaps: [Int: CGFloat] = [:]

    /// Current vertical offset of the panel from its fully-open position.
    /// 0 = open, `panelHeight` = fully hidden below the bottom edge.
    var panelOffset: CGFloat {
        let base = isPanelOpen ? 0 : panelHeight
        return min(max(base + panelDrag, 0), panelHeight)
    }

    /// 1 when fully hidden (handle fully shown), 0 when the panel is open.
    /// Drives the collapsed handle's fade as the panel is pulled up.
    var panelHiddenFraction: CGFloat {
        guard panelHeight > 0 else { return isPanelOpen ? 0 : 1 }
        return panelOffset / panelHeight
    }

    func beginPanelDrag() { isPanelDragging = true }

    func updatePanelDrag(_ translation: CGFloat) { panelDrag = translation }

    /// Settle to open or closed. A flick (fast vertical velocity) wins outright
    /// so any sudden pull down closes the panel — no need to drag it far.
    /// Slow drags fall back to the projected end position.
    func endPanelDrag(predictedTranslation: CGFloat, velocity: CGFloat) {
        let flick: CGFloat = 200   // pts/s — a light, easy flick threshold
        let willOpen: Bool
        if velocity > flick {
            willOpen = false           // flick down → close
        } else if velocity < -flick {
            willOpen = true            // flick up → open
        } else {
            let base = isPanelOpen ? 0 : panelHeight
            let projected = min(max(base + predictedTranslation, 0), panelHeight)
            willOpen = projected < panelHeight / 2
        }
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            isPanelOpen = willOpen
            panelDrag = 0
            isPanelDragging = false
        }
    }

    /// The bottom panel's selected tab. Lives here (not as local view state)
    /// so it's remembered when the panel collapses and reopens.
    @Published var selectedPanelTab: Int = 0
    /// Whether the tab bar shows a tab as chosen. Off when a saved collage
    /// opens (nothing chosen, panel down) until a tab is tapped.
    @Published var panelTabShown = true

    /// A new collage: Images chosen and its panel up.
    func openImagesPanel() {
        selectedPanelTab = 0
        panelTabShown = true
        withAnimation(.easeInOut(duration: 0.25)) { isPanelOpen = true }
    }
    /// Which half of the Looks tab shows: the filters or the Edit sliders.
    @Published var looksPage: LooksPanel.Page = .filter
    /// Which part of the Layout tab shows: layout, border or canvas.
    @Published var layoutPage: LayoutPanel.Page = .layout

    /// Whether the top ratio panel is showing. In state (not local view state)
    /// so a canvas tap/drag can dismiss it the same way it does the bottom panel.
    @Published var isRatioOpen: Bool = false

    /// Open the ratio panel, hiding the bottom panel while it's up.
    func openRatio() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isPanelOpen = false
            isRatioOpen = true
        }
    }

    /// Close the ratio panel. Like the bottom panel, this leaves the canvas
    /// ready to use immediately (no second tap needed).
    func closeRatio() {
        guard isRatioOpen else { return }
        withAnimation(.easeInOut(duration: 0.25)) { isRatioOpen = false }
    }

    /// Collapse the panel (used when the user starts interacting with the
    /// canvas, so the same gesture that hides the panel also does the work).
    func collapsePanel(animated: Bool = true) {
        guard isPanelOpen else { return }
        var transaction = Transaction(animation: animated ? .easeInOut(duration: 0.25) : nil)
        transaction.disablesAnimations = !animated
        withTransaction(transaction) {
            isPanelOpen = false
            textEditTargetId = nil
            protrusionTargetId = nil
            panelDrag = 0
            isPanelDragging = false
        }
    }

    // MARK: - Selected photo (tap: the tab bar becomes its tools)

    /// The box tapped (or held) last; its tools replace the tabs.
    @Published var selectedImageId: UUID?
    /// The box whose picture the Replace picker swaps.
    @Published var boxActionTargetId: UUID? = nil
    @Published var showReplacePicker: Bool = false
    /// When a box last took a tap, so the canvas's own tap handler (which
    /// sees the same tap) leaves the selection alone.
    private var lastBoxTap: Date = .distantPast

    /// The selected box, while it's on the page showing.
    var selectedImage: CollageImage? {
        selectedImageId.flatMap { id in images.first { $0.id == id } }
    }

    /// A tap on a box selects it, or lets it go if it was selected.
    func toggleSelection(_ id: UUID) {
        selectImage(selectedImageId == id ? nil : id)
    }

    /// Selects a box (nil: none). Its tools take the panel's place; letting
    /// it go always comes back to the plain tab bar: no tab chosen, no
    /// panel up. `keepTab`: for leaving it to open a tab or an editor.
    func selectImage(_ id: UUID?, keepTab: Bool = false) {
        lastBoxTap = Date()
        guard id != selectedImageId else { return }
        if id != nil {
            endTextEditing()
            endProtrusionEditing()
            // Editing another photo ends too: its tools come back for this one.
            endPhotoEditing()
            closeRatio()
            collapsePanel()
        }
        let wasSelected = selectedImageId != nil
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { selectedImageId = id }
        if id == nil, wasSelected, !keepTab {
            collapsePanel()
            withAnimation(.easeInOut(duration: 0.25)) { panelTabShown = false }
        }
    }

    // MARK: - Shared import (Share Extension)
    @Published var pendingSharedImages: [CollageImage] = []
    /// Their inbox files, deleted once the photos are added or discarded.
    var pendingSharedFiles: [URL] = []

    /// The pending shared photos, taken: their inbox files go too.
    private func takePendingShared() -> [CollageImage] {
        let shared = pendingSharedImages
        pendingSharedImages = []
        SharedInbox.remove(pendingSharedFiles)
        pendingSharedFiles = []
        return shared
    }
    @Published var showSharedImportChoice: Bool = false

    // MARK: - Undo / redo (see History.swift)
    @Published var canUndo = false
    @Published var canRedo = false
    /// "Undo" / "Redo" flashed over the canvas after a shake.
    /// The last save of the open collage didn't go through.
    @Published var saveFailed = false
    @Published var historyToast: String? = nil
    /// The toast's symbol, when it isn't an undo / redo one.
    var historyToastIcon: String? = nil
    var historyToastToken = 0
    static let maxUndoSteps = 40
    var undoStack: [CollageSnapshot] = []
    var redoStack: [CollageSnapshot] = []
    /// The document as of the last recorded step.
    var historyCommitted: CollageSnapshot?
    var historyWatcher: AnyCancellable?

    /// Called after every recorded change (and undo / redo).
    func documentDidChange() { scheduleAutosave() }

    // MARK: - Saved collages (see Projects.swift)
    let projectStore = ProjectStore()
    /// The collage being edited; it's saved under this id.
    var currentProjectId = UUID()
    var autosaveWork: DispatchWorkItem?
    /// When the Collages list picture was last rendered (see saveProjectNow).
    var lastThumbnailAt: Date = .distantPast
    /// A saved collage is being read (after the open one's save).
    var isOpeningProject = false
    /// Edited since it was opened or last saved. Leaving a collage that
    /// wasn't touched doesn't save it again (that would re-render its
    /// thumbnail before the photos are drawn, leaving it empty).
    var hasUnsavedChanges = false
    /// Photo files already written for this collage, by picture.
    var savedImageFiles: [ObjectIdentifier: (original: OriginalPicture, file: String)] = [:]
    /// Photo files the open collage lists but couldn't load: never deleted
    /// as unused by a save.
    var unloadedImageFiles: Set<String> = []
    /// True while a saved collage loads (at launch or from the list).
    @Published var isRestoringProject = false
    var isRenderingThumbnail = false

    /// Photos whose subject has been looked for (see SmartLayout.swift).
    var focusChecked: Set<UUID> = []

    // MARK: - Export
    /// While true, image boxes draw the export's pictures instead of the
    /// canvas proxies: true only while an export picture renders (see renderCurrentPage):
    /// the boxes on screen keep drawing their proxies meanwhile. Not
    /// published: it's on and off again within one render.
    var renderFullResolution: Bool = false
    @Published var isExporting: Bool = false
    /// 0…1 progress of a multi-page export (pages rendered / total).
    @Published var exportProgress: Double = 0
    @Published var exportTotalPages: Int = 0

    /// Drives the "Exporting" dialog shown while exporting.
    enum SavePhase: Equatable {
        case idle, saving
    }
    @Published var savePhase: SavePhase = .idle
    /// Files written by the last export ("Collage 01.jpg" …).
    @Published var exportedFiles: [URL] = []
    @Published var showExportSheet: Bool = false
    /// Edit → Auto is working out the page.
    @Published var isAutoAdjusting = false
    /// Where Auto was pressed, by page id (for its on / off).
    @Published var autoApplied: [UUID: AutoApplied] = [:]
    /// Set when pages couldn't be exported; shown as an alert.
    @Published var exportProblem: String?
    /// Some pages failed but the others went to the share sheet: said
    /// once that closes (an alert can't show over it).
    var exportProblemAfterSheet: String?
    /// Cancel in the "Exporting" dialog: stops before the next picture.
    @Published var exportCancelRequested = false
    /// Asks the user whether to export the current page or all pages.
    @Published var showExportOptions: Bool = false
    /// About das Kolaž (press and hold the logo).
    @Published var showAbout = false
    /// "Export…" on a saved collage: Export Options once it's open.
    var exportAfterOpening = false
    /// A page's settings, copied from the page menu to paste onto others.
    @Published var copiedPageLook: CopiedPageLook? = nil
    /// The Paste Settings sheet; `pasteToAllOthers` starts it on every other page.
    @Published var showPastePageLook: Bool = false
    var pasteToAllOthers = false

    /// True when any page has at least one image.
    var hasAnyImages: Bool {
        pages.contains { !$0.images.isEmpty }
    }

    /// Total number of images across all pages.
    var totalImageCount: Int {
        pages.reduce(0) { $0 + $1.images.count }
    }

    // MARK: - Image management

    func addImages(_ newImages: [PlatformImage]) {
        addPreparedImages(newImages.map { CollageImage(image: $0) })
    }

    /// Adds a transparent 300×300 "empty image" placeholder that occupies a
    /// slot like any other image, leaving a deliberate gap in the collage.
    func addEmptyImage() {
        addPreparedImages([CollageImage.emptyPlaceholder()])
    }

    // MARK: - Text images

    /// Text box being edited in the panel (nil = not editing text).
    @Published var textEditTargetId: UUID? = nil
    /// A text box just added: its panel starts with the keyboard up.
    var focusTextOnOpen = false

    /// Adds a text box rendered as an image (in the last used look) and
    /// opens it for editing.
    func addTextImage() {
        var style = TextBoxStyle.lastUsed
        // The text must read against what's behind it: its own fill, or —
        // when that's see-through — the page's background. Too close
        // (white on white), it starts black or white instead.
        let fill = style.backgroundColor.srgbComponents[3] > 0.5 ? style.backgroundColor : backgroundColor
        if style.textColor.contrastRatio(with: fill) < 3 {
            style.textColor = Color.black.contrastRatio(with: fill) >= Color.white.contrastRatio(with: fill)
                ? .black : .white
        }
        let image = CollageImage.textImage(style: style)
        addPreparedImages([image])
        if currentPage.images.contains(where: { $0.id == image.id }) {
            focusTextOnOpen = true
            beginEditText(id: image.id)
        }
    }

    /// The edit button on a text box edits it live: the panel swaps to the text
    /// properties while the text itself updates on the collage.
    func beginEditText(id: UUID) {
        lastTextTap = Date()
        guard textEditTargetId != id || !isPanelOpen else { return }
        Diagnostics.log("edit text")
        closeRatio()
        withAnimation(.easeInOut(duration: 0.25)) {
            // From the full-screen preview, back to editing.
            chromeHidden = false
            textEditTargetId = id
            isPanelOpen = true
        }
    }

    func endTextEditing() {
        guard textEditTargetId != nil else { return }
        withAnimation(.easeInOut(duration: 0.2)) { textEditTargetId = nil }
    }

    // MARK: - Protrusion

    /// The photo whose protrusion settings fill the panel (long-press menu →
    /// Protrude), like text editing.
    @Published var protrusionTargetId: UUID? = nil
    /// Subject masks by image id (made on demand, kept for the session).
    @Published private(set) var subjectMasks: [UUID: SubjectMask] = [:]
    private var maskInFlight: Set<UUID> = []
    /// The in-flight pan / pinch of a protruding photo, so its protrusion
    /// follows the finger live. Deliberately not @Published: only the
    /// protrusion layer observes it, so a gesture doesn't redraw the app.
    let liveGesture = LiveGesture()

    func beginProtrusion(id: UUID) {
        Diagnostics.log("protrude")
        closeRatio()
        textEditTargetId = nil
        withAnimation(.easeInOut(duration: 0.25)) {
            protrusionTargetId = id
            isPanelOpen = true
        }
        if let img = images.first(where: { $0.id == id }) {
            requestSubjectMask(for: img)
            turnOnProtrusionIfNew(id)
        }
    }

    /// Opening Cutout turns it on (once the subject is known) for a photo
    /// that doesn't break out yet, over the top and right edges.
    private func turnOnProtrusionIfNew(_ id: UUID) {
        guard protrusionTargetId == id, let img = images.first(where: { $0.id == id }),
              img.protrusion == nil, subjectMask(for: img)?.mask != nil else { return }
        setProtrusion(.initial, for: id)
    }

    func endProtrusionEditing() {
        guard protrusionTargetId != nil else { return }
        withAnimation(.easeInOut(duration: 0.2)) { protrusionTargetId = nil }
    }

    /// The subject mask for a photo, if made (and still matching its image).
    func subjectMask(for img: CollageImage) -> SubjectMask? {
        guard let m = subjectMasks[img.id], m.source == ObjectIdentifier(img.original) else { return nil }
        return m
    }

    func isFindingSubject(_ id: UUID) -> Bool { maskInFlight.contains(id) }

    /// Finds the photo's subject with Vision, off the main thread, once.
    func requestSubjectMask(for img: CollageImage) {
        guard img.canProtrude, subjectMask(for: img) == nil, !maskInFlight.contains(img.id) else { return }
        let id = img.id, original = img.original
        maskInFlight.insert(id)
        objectWillChange.send()
        // Vision blocks its thread: on its own queue, off the shared task
        // pool that grading needs (as focus finding).
        Self.maskQueue.async {
            let mask = autoreleasepool {
                SubjectMasker.makeMask(for: original.scaled(maxEdge: SubjectMasker.maskLongEdge),
                                       source: ObjectIdentifier(original))
            }
            DispatchQueue.main.async {
                self.maskInFlight.remove(id)
                self.subjectMasks[id] = mask
                Diagnostics.log("subject \(mask.mask == nil ? "not found" : "found (\(mask.instances.count))")")
                self.turnOnProtrusionIfNew(id)
            }
        }
    }

    nonisolated static let maskQueue = DispatchQueue(label: "subject masks", qos: .userInitiated)

    func setProtrusion(_ edges: ProtrusionEdges?, for id: UUID) {
        guard let pi = pageIndex(containing: id),
              let idx = pages[pi].images.firstIndex(where: { $0.id == id }) else { return }
        pages[pi].images[idx].protrusion = edges
    }

    func setProtrusionEffect(_ effect: ProtrusionEffect, for id: UUID) {
        guard let pi = pageIndex(containing: id),
              let idx = pages[pi].images.firstIndex(where: { $0.id == id }) else { return }
        pages[pi].images[idx].protrusionEffect = effect
    }

    /// Choose which subjects protrude (nil = all of them).
    func setProtrusionObjects(_ objects: Set<Int>?, for id: UUID) {
        guard let pi = pageIndex(containing: id),
              let idx = pages[pi].images.firstIndex(where: { $0.id == id }) else { return }
        pages[pi].images[idx].protrusionObjects = objects
    }

    /// Tapping a subject in the photo (Protrude panel open): include it or
    /// leave it out. At least one subject always stays in.
    func toggleProtrusionObject(_ index: Int, for id: UUID) {
        guard let img = images.first(where: { $0.id == id }),
              let count = subjectMask(for: img)?.instances.count, count > 1 else { return }
        var chosen = img.protrusionObjects ?? Set(0..<count)
        if chosen.contains(index) { chosen.remove(index) } else { chosen.insert(index) }
        guard !chosen.isEmpty else { return }
        setProtrusionObjects(chosen.count == count ? nil : chosen, for: id)
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }

    /// The subjects that protrude, as one mask with its bounds (all of them,
    /// or the chosen ones merged).
    private var mergedShapes: [UUID: (source: ObjectIdentifier, objects: Set<Int>, mask: CGImage, bounds: CGRect)] = [:]

    func protrusionShape(for img: CollageImage) -> (mask: CGImage, bounds: CGRect)? {
        guard let subject = subjectMask(for: img), let all = subject.mask else { return nil }
        guard let objects = img.protrusionObjects, subject.instances.count > 1 else {
            return (all, subject.bounds)
        }
        let picked = objects.sorted().filter { $0 < subject.instances.count }.map { subject.instances[$0] }
        guard !picked.isEmpty else { return (all, subject.bounds) }
        let source = ObjectIdentifier(img.original)
        if let m = mergedShapes[img.id], m.source == source, m.objects == objects {
            return (m.mask, m.bounds)
        }
        let bounds = picked.dropFirst().reduce(picked[0].bounds) { $0.union($1.bounds) }
        if picked.count == 1 { return (picked[0].mask, bounds) }
        let id = img.id, masks = picked.map(\.mask)
        let made = cutoutWork("union \(id) \(objects.sorted())") {
            SubjectMasker.union(masks)
        } store: { (mask: CGImage?) in
            if let mask { self.mergedShapes[id] = (source, objects, mask, bounds) }
        }
        if let made, let mask = made { return (mask, bounds) }
        // Meanwhile: the last shape this photo had, else all its subjects.
        if let m = mergedShapes[img.id], m.source == source { return (m.mask, m.bounds) }
        return (all, subject.bounds)
    }

    /// Cutout shapes in the making, by job.
    private var cutoutJobs: Set<String> = []

    /// A cutout shape (Vision / Core Image work): made right away for an
    /// offscreen render (the export needs it now), else on the mask queue
    /// — never in the middle of drawing the screen — then `store`d and the
    /// canvas redrawn. Returns what was made now (offscreen only).
    private func cutoutWork<T>(_ job: String, make: @escaping () -> T, store: @escaping (T) -> Void) -> T? {
        if isRenderingOffscreen {
            let value = make()
            store(value)
            return value
        }
        guard !cutoutJobs.contains(job) else { return nil }
        cutoutJobs.insert(job)
        Self.maskQueue.async {
            let value = autoreleasepool { make() }
            DispatchQueue.main.async {
                self.cutoutJobs.remove(job)
                store(value)
                self.objectWillChange.send()
            }
        }
        return nil
    }

    /// Outline polylines of each subject (for the preview), by image id.
    private var instanceOutlines: [UUID: (source: ObjectIdentifier, outlines: [[[CGPoint]]])] = [:]

    func subjectInstanceOutlines(for img: CollageImage) -> [[[CGPoint]]] {
        guard let subject = subjectMask(for: img) else { return [] }
        let source = ObjectIdentifier(img.original)
        if let o = instanceOutlines[img.id], o.source == source { return o.outlines }
        let id = img.id, masks = subject.instances.map(\.mask)
        return cutoutWork("outlines \(id)") {
            masks.map { SubjectMasker.outline(of: $0) }
        } store: { outlines in
            self.instanceOutlines[id] = (source, outlines)
        } ?? []
    }

    /// Subject masks grown by a radius (mask pixels), for the Border effect.
    private var dilatedMasks: [UUID: (source: ObjectIdentifier, objects: Set<Int>?, radius: Int, image: CGImage)] = [:]

    /// Outline polylines of the subject grown by `radius` mask pixels (the
    /// line patterned Border styles run along it).
    private var subjectOutlines: [UUID: (source: ObjectIdentifier, objects: Set<Int>?, radius: Int, outline: [[CGPoint]])] = [:]

    func subjectOutline(for img: CollageImage, radius: Int, allowStale: Bool = false) -> [[CGPoint]] {
        let source = ObjectIdentifier(img.original), objects = img.protrusionObjects
        let cached = subjectOutlines[img.id].flatMap { $0.source == source && $0.objects == objects ? $0 : nil }
        if let cached, cached.radius == radius || allowStale { return cached.outline }
        // The grown mask first (made the same way); until both are there,
        // the last outline at another radius stands in.
        guard let grown = dilatedSubjectMask(for: img, radius: radius, exact: true) else { return cached?.outline ?? [] }
        let id = img.id
        let made = cutoutWork("outline \(id) \(radius)") {
            SubjectMasker.outline(of: grown)
        } store: { outline in
            self.subjectOutlines[id] = (source, objects, radius, outline)
        }
        return made ?? cached?.outline ?? []
    }

    /// `allowStale`: during a live pinch, reuse the last grown mask whatever
    /// its radius (growing one per frame is too slow); it's redone on release.
    /// Made off the main thread (see cutoutWork): until it's there, the
    /// last one at another radius stands in, unless `exact`.
    func dilatedSubjectMask(for img: CollageImage, radius: Int, allowStale: Bool = false,
                            exact: Bool = false) -> CGImage? {
        guard let mask = protrusionShape(for: img)?.mask else { return nil }
        let source = ObjectIdentifier(img.original), objects = img.protrusionObjects
        let cached = dilatedMasks[img.id].flatMap { $0.source == source && $0.objects == objects ? $0 : nil }
        if let cached, cached.radius == radius || allowStale { return cached.image }
        let id = img.id
        let made = cutoutWork("dilate \(id) \(radius) \(objects.map { $0.sorted() } ?? [])") {
            SubjectMasker.dilate(mask, radius: radius)
        } store: { grown in
            if let grown { self.dilatedMasks[id] = (source, objects, radius, grown) }
        }
        if let made { return made }
        return exact ? nil : cached?.image
    }

    /// The box edges the photo's subject currently crosses — where a
    /// protrusion would actually show, given its zoom, pan and rotation.
    func protrudableEdges(for id: UUID) -> ProtrusionEdges {
        guard let img = images.first(where: { $0.id == id }), let shape = protrusionShape(for: img),
              let box = imageFrames[id]?.size,
              let placement = ImagePlacement.compute(natural: img.naturalSize, boxSize: box, zoom: img.zoom,
                                                     rotation: img.rotation,
                                                     pan: Self.panPixels(img.panOffset, in: box))
        else { return [] }
        let b = shape.bounds
        let corners = [placement.boxPoint(b.minX, b.minY), placement.boxPoint(b.maxX, b.minY),
                       placement.boxPoint(b.minX, b.maxY), placement.boxPoint(b.maxX, b.maxY)]
        let tolerance: CGFloat = 1
        var edges: ProtrusionEdges = []
        if corners.contains(where: { $0.y < -box.height / 2 - tolerance }) { edges.insert(.top) }
        if corners.contains(where: { $0.y > box.height / 2 + tolerance }) { edges.insert(.bottom) }
        if corners.contains(where: { $0.x < -box.width / 2 - tolerance }) { edges.insert(.left) }
        if corners.contains(where: { $0.x > box.width / 2 + tolerance }) { edges.insert(.right) }
        return edges
    }

    /// A tap on a text box also reaches the canvas-wide tap handlers, in no
    /// guaranteed order. They defer to the next runloop tick and stand down
    /// when the tap just opened a text box.
    private var lastTextTap: Date = .distantPast

    /// Canvas taps dismiss whatever is open: text editing, panel, ratio sheet.
    func handleCanvasTap() {
        DispatchQueue.main.async { [self] in
            guard Date().timeIntervalSince(lastTextTap) > 0.25 else { return }
            // A tab's panel put away this way lets go of the tab too, as a
            // second tap on the tab does.
            let tabPanel = isPanelOpen && textEditTargetId == nil && protrusionTargetId == nil
                && photoEditTargetId == nil
            endTextEditing()
            collapsePanel()
            closeRatio()
            if tabPanel { withAnimation(.easeInOut(duration: 0.25)) { panelTabShown = false } }
        }
        // A box's own tap comes a moment later (it first waits to see if
        // it's a double tap): only a tap no box took lets the selection go.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [self] in
            guard Date().timeIntervalSince(lastBoxTap) > 0.6 else { return }
            selectImage(nil)
        }
    }

    func textStyle(for id: UUID) -> TextBoxStyle? {
        pages.flatMap(\.images).first { $0.id == id }?.textStyle
    }

    /// Re-renders a text image with an edited style, keeping its slot and
    /// transform. The bitmap takes the shape of the box it lives in.
    func applyTextStyle(_ style: TextBoxStyle, to id: UUID) {
        guard let pi = pageIndex(containing: id),
              let idx = pages[pi].images.firstIndex(where: { $0.id == id }) else { return }
        let box = pages[pi].images[idx].lastBoxSize
        let size = CollageImage.textRenderSize(forBox: box)
        pages[pi].images[idx].setImage(CollageImage.renderTextImage(
            style: style, size: size, boxLongEdge: box.width > 1 ? max(box.width, box.height) : nil))
        pages[pi].images[idx].textStyle = style
    }

    /// Adds images whose proxies were already generated off the main thread.
    /// Fills the current page up to the per-page limit, then spills into new
    /// pages (up to the page limit; any excess beyond that is dropped).
    /// A fresh batch: up to this many photos stay on one page (10 still
    /// fits one balanced page); more are spread over pages of about
    /// `imagesPerPage`, as evenly as possible.
    static let onePageLimit = 10
    static let imagesPerPage = 9

    /// Pages a fresh batch of `n` photos starts on: one up to 10, then
    /// enough for about 9 each (12 → 2×6, 19 → 7+6+6, 27 → 3×9).
    static func initialPageCount(for n: Int) -> Int {
        guard n > onePageLimit else { return 1 }
        return min(maxPages, Int((Double(n) / Double(imagesPerPage)).rounded(.up)))
    }

    /// The most balanced grid for `photos` on a canvas of `canvas`: the
    /// column count whose cells come closest to the photos' typical shape,
    /// preferring counts that fill every column evenly (9 → 3×3, 6 → 3×2
    /// on a square, 2×3 on a tall story canvas).
    /// `shapeOf` is the set of photos whose typical shape counts (the whole
    /// batch, so pages with as many photos get the same grid).
    static func balancedColumns(for n: Int, shapeOf photos: [CollageImage], canvas: CGSize) -> Int {
        guard n > 1, !photos.isEmpty else { return 1 }
        let shapes = photos.map { $0.naturalSize.width / max($0.naturalSize.height, 1) }.sorted()
        let photoAspect = max(shapes[shapes.count / 2], 0.2)
        var best = 1, bestCost = Double.infinity
        for k in 1...min(n, 6) {
            let rows = Int((Double(n) / Double(k)).rounded(.up))
            let cell = (Double(canvas.width) / Double(k)) / (Double(canvas.height) / Double(rows))
            var cost = abs(log(cell / Double(photoAspect)))
            if n % k != 0 { cost += 0.35 }          // uneven columns
            // A tie goes to more columns (6 on a square → 3×2, not 2×3).
            if cost <= bestCost + 1e-9 { best = k; bestCost = cost }
        }
        return best
    }

    /// Adds images to page `target` (default: the current page), spilling
    /// onto new pages once it's full.
    /// Picked photos read in, with "Adding 7 of 30" on screen, and a word
    /// about any that couldn't be read.
    func readPicked(_ items: [PhotosPickerItem]) async -> [CollageImage] {
        let total = items.count
        importProgress = ImportProgress(done: 0, total: total)
        let result = await CollageImage.prepare(items) { [weak self] done in
            self?.importProgress = ImportProgress(done: done, total: total)
        }
        importProgress = nil
        if result.failed > 0 {
            Diagnostics.log("\(result.failed) of \(total) photos couldn't be read")
            flashToast(result.failed == 1 ? "1 photo couldn't be added" : "\(result.failed) photos couldn't be added",
                       icon: "exclamationmark.triangle.fill", seconds: 3)
        }
        return result.images
    }

    /// After adding: says how many photos didn't fit.
    func reportPhotosLeftOut(_ count: Int) {
        guard count > 0 else { return }
        flashToast(count == 1 ? "1 photo didn't fit (\(Self.maxPosts) posts at most)"
                              : "\(count) photos didn't fit (\(Self.maxPosts) posts at most)",
                   icon: "exclamationmark.triangle.fill", seconds: 3)
    }

    /// Adds the photos; returns how many didn't fit (past the page limit).
    @discardableResult
    func addPreparedImages(_ prepared: [CollageImage], toPage target: Int? = nil) -> Int {
        defer { detectFocusPoints() }
        let wasEmpty = pages.allSatisfy { $0.images.isEmpty }

        // Fresh collage: one page up to 10 photos, else pages of about 9,
        // evened out, each laid out as the most balanced grid.
        if wasEmpty {
            let target = max(pages.count, Self.initialPageCount(for: prepared.count))
            distributeEvenly(prepared, intoPages: target)
            withAnimation(.easeInOut(duration: 0.25)) { isPanelOpen = true }
            return 0
        }

        var remaining = prepared[...]
        var pi = target.flatMap { pages.indices.contains($0) ? $0 : nil } ?? safePageIndex

        while !remaining.isEmpty {
            let capacity = Self.maxImagesPerPage - pages[pi].images.count
            if capacity > 0 {
                let pageWasEmpty = pages[pi].images.isEmpty
                let chunk = remaining.prefix(capacity)
                pages[pi].images.append(contentsOf: chunk)
                pages[pi].order.append(contentsOf: chunk.map(\.id))
                // First images on this page: snap the Columns setting to the
                // number of columns actually used (never above image count)
                if pageWasEmpty {
                    pages[pi].style.numCols = max(1, min(pages[pi].style.numCols,
                                                         pages[pi].images.count))
                }
                pages[pi].layout.rebuild(images: pages[pi].images,
                                         order: pages[pi].order,
                                         numCols: pages[pi].style.numCols, strip: pages[pi].style.isStrip)
                remaining = remaining.dropFirst(chunk.count)
            }
            guard !remaining.isEmpty else { break }
            guard canAddPost else { break }
            // Spill pages inherit the style of the page being filled
            pages.append(CollagePage(style: pages[pi].style.single, look: pages[pi].look))
            pi = pages.count - 1
        }

        // First images just arrived: reveal the options panel
        if wasEmpty && !pages.allSatisfy({ $0.images.isEmpty }) {
            withAnimation(.easeInOut(duration: 0.25)) {
                isPanelOpen = true
            }
        }
        return remaining.count
    }

    /// Resolves the pending Share Extension import once the user has chosen
    /// whether to start a fresh collage or append to the current one.
    func importPendingShared(replacingCurrent: Bool) {
        let shared = takePendingShared()
        guard !shared.isEmpty else { return }
        if replacingCurrent {
            startNewCollage()
        }
        addPreparedImages(shared)
    }

    /// Adds the pending shared photos to the existing collage on a fresh page
    /// appended at the end, and navigates to it. Overflow beyond the per-page
    /// limit spills onto further new pages, like a normal import.
    func importPendingSharedAsNewPage() {
        guard !pendingSharedImages.isEmpty, canAddPost else { return }
        let shared = takePendingShared()
        pages.append(CollagePage(style: currentPage.style.single, look: currentPage.look))
        currentPageIndex = pages.count - 1
        addPreparedImages(shared)
    }

    /// Spreads the current images plus the pending shared photos evenly
    /// across the defined pages.
    func importPendingSharedBurst() {
        let shared = takePendingShared()
        guard !shared.isEmpty else { return }
        let all = pages.flatMap { $0.images } + shared
        // Create enough pages for ~4 images each, but never fewer than the
        // pages that already exist.
        let target = max(pages.count, Int((Double(all.count) / 4).rounded(.up)))
        distributeEvenly(all, intoPages: target)
    }

    func discardPendingShared() {
        _ = takePendingShared()
    }

    /// Replaces the image content of an existing box, keeping its position in
    /// the layout. Pan/zoom reset because they are meaningless for the new image.
    func replaceImage(id: UUID, with prepared: CollageImage) {
        guard let pi = pageIndex(containing: id),
              let idx = pages[pi].images.firstIndex(where: { $0.id == id }) else { return }
        pages[pi].images[idx].setImage(prepared)
        focusChecked.remove(id)
        // The old picture's cutout must not stay with the new one (the
        // caches know a picture by its address, which can be reused).
        subjectMasks[id] = nil
        mergedShapes[id] = nil
        instanceOutlines[id] = nil
        dilatedMasks[id] = nil
        subjectOutlines[id] = nil
        defer { detectFocusPoints() }
        pages[pi].images[idx].panOffset = .zero
        pages[pi].images[idx].framedByUser = false
        pages[pi].images[idx].zoom = 1.0
        pages[pi].images[idx].lastBoxSize = .zero
        // Swap the new picture into its box in place, keeping the user's
        // arrangement and sizing (rebuild only if it isn't laid out yet).
        if let pos = pages[pi].layout.position(of: id) {
            let s = pages[pi].images[idx].naturalSize
            pages[pi].layout.columns[pos.col][pos.row] =
                ColumnItem(imageId: id, aspectRatio: s.height / max(s.width, 1))
        } else {
            pages[pi].layout.rebuild(images: pages[pi].images,
                                     order: pages[pi].order,
                                     numCols: pages[pi].style.numCols, strip: pages[pi].style.isStrip)
        }
    }

    func removeImage(id: UUID) {
        guard let pi = pageIndex(containing: id) else { return }
        pages[pi].images.removeAll { $0.id == id }
        pages[pi].order.removeAll { $0 == id }
        pages[pi].layout.resetGrows()
        pages[pi].layout.rebuild(images: pages[pi].images,
                                 order: pages[pi].order,
                                 numCols: pages[pi].style.numCols, strip: pages[pi].style.isStrip)
        imageFrames.removeValue(forKey: id)
        if draggingId == id || dropTargetId == id {
            clearSwapDrag()
        }
        forgetRemovedImages()
    }

    // MARK: - Page management

    func pageIndex(containing id: UUID) -> Int? {
        pages.firstIndex { $0.images.contains { $0.id == id } }
    }

    func addPage() {
        guard canAddPost else { return }
        // New pages start with the current page's style
        pages.append(CollagePage(style: currentPage.style.single, look: currentPage.look))
        currentPageIndex = pages.count - 1
    }

    func deletePage(at index: Int) {
        guard pages.count > 1, pages.indices.contains(index) else { return }
        for img in pages[index].images {
            imageFrames.removeValue(forKey: img.id)
        }
        pages.remove(at: index)
        // Stay on the page that was showing (it moves up one if an earlier
        // page went).
        if index < currentPageIndex { currentPageIndex -= 1 }
        currentPageIndex = min(currentPageIndex, pages.count - 1)
        forgetRemovedImages()
    }

    /// Moves an image to another page (appended at the end), resetting its
    /// pan/zoom since the box geometry changes.
    func moveImage(id: UUID, toPage target: Int) {
        guard pages.indices.contains(target),
              pages[target].images.count < Self.maxImagesPerPage,
              let src = pageIndex(containing: id), src != target,
              let idx = pages[src].images.firstIndex(where: { $0.id == id }) else { return }

        var img = pages[src].images.remove(at: idx)
        pages[src].order.removeAll { $0 == id }
        img.panOffset = .zero
        img.framedByUser = false
        img.zoom = 1.0
        img.rotation = 0
        img.lastBoxSize = .zero
        pages[target].images.append(img)
        pages[target].order.append(id)
        // A new image dropped on the page: columns follow the images used
        pages[target].style.numCols = min(pages[target].images.count, 6)

        for pi in [src, target] {
            pages[pi].layout.resetGrows()
            pages[pi].layout.rebuild(images: pages[pi].images,
                                     order: pages[pi].order,
                                     numCols: pages[pi].style.numCols, strip: pages[pi].style.isStrip)
        }
        imageFrames.removeValue(forKey: id)
    }

    /// Swaps the positions of two pages in the page list, keeping the
    /// selection on the same page content.
    func swapPages(_ a: Int, _ b: Int) {
        guard pages.indices.contains(a), pages.indices.contains(b), a != b else { return }
        pages.swapAt(a, b)
        if currentPageIndex == a {
            currentPageIndex = b
        } else if currentPageIndex == b {
            currentPageIndex = a
        }
    }

    func moveImageToNewPage(id: UUID) {
        guard canAddPost else { return }
        pages.append(CollagePage(style: currentPage.style.single, look: currentPage.look))
        moveImage(id: id, toPage: pages.count - 1)
    }

    /// Collapses the whole collage onto a single page, deleting the others.
    func mergeAllOntoOnePage() {
        // Never leave photos out (the menu doesn't offer it then either).
        guard totalImageCount <= Self.maxImagesPerPage else { return }
        let allImages = pages.flatMap { $0.images }.prefix(Self.maxImagesPerPage).map { img -> CollageImage in
            var i = img
            i.panOffset = .zero
            i.framedByUser = false
            i.zoom = 1.0
            i.lastBoxSize = .zero
            return i
        }
        var page = CollagePage(style: currentPage.style.single, look: currentPage.look)
        page.images = Array(allImages)
        page.order = allImages.map(\.id)
        page.style.numCols = max(1, min(allImages.count, 6))
        page.layout.rebuild(images: page.images, order: page.order, numCols: page.style.numCols, strip: page.style.isStrip)
        pages = [page]
        currentPageIndex = 0
        imageFrames.removeAll()
        emptySlotFrames.removeAll()
        clearSwapDrag()
    }

    /// Spreads all images evenly across the current pages, keeping the page
    /// count. Each page gets ceil(total / pages) images; the last populated
    /// page takes the remainder.
    func burstAcrossPages(adding extra: [CollageImage] = []) {
        let allImages = pages.flatMap { $0.images } + extra
        guard !allImages.isEmpty else { return }
        distributeEvenly(allImages, intoPages: pages.count)
    }

    /// How many pages "Burst!" will create for a given image count. Small
    /// sets go one-per-page for a dramatic spread; larger sets target a nicely
    /// balanced grid of ≈ 6 images per page (3 columns × 2 rows), capped at
    /// the page limit.
    static func burstPageCount(for n: Int) -> Int {
        guard n > 0 else { return 0 }
        if n <= 5 { return min(n, maxPages) }
        let idealPerPage = 6.0    // 3 columns × 2 rows
        return min(maxPages, max(1, Int((Double(n) / idealPerPage).rounded(.up))))
    }

    /// Pages "Burst!" will produce for the current collage.
    var burstPageCount: Int { Self.burstPageCount(for: totalImageCount) }

    /// Column count for a Burst! page, biased toward landscape grids with a
    /// tendency of at least 3 columns (so 5–6 images read as 3×2, not 2×3).
    static func burstColumns(for count: Int) -> Int {
        if count <= 1 { return 1 }
        if count == 2 { return 2 }
        return max(3, min(6, Int((Double(count) * 1.5).squareRoot().rounded())))
    }

    /// "Burst!" — spreads every image across an automatically balanced number
    /// of pages (see `burstPageCount`), each laid out as a landscape-leaning grid.
    func burstBalanced() {
        let allImages = pages.flatMap { $0.images }
        guard !allImages.isEmpty else { return }
        distributeEvenly(allImages,
                         intoPages: Self.burstPageCount(for: allImages.count),
                         columnsFor: { Self.burstColumns(for: $0) })
    }

    /// Rebuilds the document as `pageCount` pages holding the given images
    /// spread evenly, each page getting a balanced grid (≈ half its image
    /// count as columns).
    private func distributeEvenly(_ images: [CollageImage], intoPages requestedPages: Int,
                                  columnsFor: ((Int) -> Int)? = nil) {
        guard !images.isEmpty else { return }
        let pageCount = min(Self.maxPages, max(1, requestedPages))
        let styleTemplate = currentPage.style, lookTemplate = currentPage.look
        // As even as possible: page sizes differ by one at most (19 over 3
        // pages → 7, 6, 6 — never 7, 7, 5).
        let base = images.count / pageCount, extra = images.count % pageCount

        var newPages: [CollagePage] = []
        var idx = 0
        for p in 0..<pageCount {
            let perPage = min(Self.maxImagesPerPage, base + (p < extra ? 1 : 0))
            var page = CollagePage(style: styleTemplate.single, look: lookTemplate)
            var chunk: [CollageImage] = []
            while chunk.count < perPage && idx < images.count {
                var img = images[idx]
                img.panOffset = .zero
                img.framedByUser = false
                img.zoom = 1.0
                img.lastBoxSize = .zero
                chunk.append(img)
                idx += 1
            }
            page.images = chunk
            // The most balanced grid for these photos on this canvas (9 → 3×3).
            // Callers may override with a different strategy (e.g. Burst!'s
            // landscape bias).
            page.style.numCols = columnsFor?(chunk.count)
                ?? Self.balancedColumns(for: chunk.count, shapeOf: images, canvas: canvasSize)
            // Tall photos into the tall boxes, wide ones into the wide.
            page.order = Self.fittingOrder(chunk, numCols: page.style.numCols,
                                           canvas: canvasSize, rows: page.style.isRows)
            page.layout.rebuild(images: page.images, order: page.order,
                                numCols: page.style.numCols, strip: page.style.isStrip)
            newPages.append(page)
        }

        pages = newPages
        currentPageIndex = 0
        imageFrames.removeAll()
        emptySlotFrames.removeAll()
        clearSwapDrag()
    }

    /// Redistributes the whole collage so every page holds exactly one image,
    /// creating pages as needed (up to the page limit; if images outnumber
    /// the limit, the remainder stacks on the last page).
    func distributeOneImagePerPage() {
        let allImages = pages.flatMap { $0.images }
        guard !allImages.isEmpty,
              allImages.count <= Self.maxPages + Self.maxImagesPerPage - 1 else { return }
        let styleTemplate = currentPage.style, lookTemplate = currentPage.look

        var newPages: [CollagePage] = []
        for var img in allImages.prefix(Self.maxPages) {
            img.panOffset = .zero
            img.framedByUser = false
            img.zoom = 1.0
            img.lastBoxSize = .zero
            var page = CollagePage(style: styleTemplate.single, look: lookTemplate)
            page.style.numCols = 1
            page.images = [img]
            page.order = [img.id]
            page.layout.rebuild(images: page.images, order: page.order, numCols: 1)
            newPages.append(page)
        }

        // Overflow beyond the page limit stacks on the last page
        let overflow = allImages.dropFirst(Self.maxPages)
        if !overflow.isEmpty, var last = newPages.last {
            for var img in overflow.prefix(Self.maxImagesPerPage - last.images.count) {
                img.panOffset = .zero
                img.framedByUser = false
                img.zoom = 1.0
                img.lastBoxSize = .zero
                last.images.append(img)
                last.order.append(img.id)
            }
            last.style.numCols = min(last.images.count, 6)
            last.layout.rebuild(images: last.images, order: last.order,
                                numCols: last.style.numCols, strip: last.style.isStrip)
            newPages[newPages.count - 1] = last
        }

        pages = newPages
        currentPageIndex = 0
        imageFrames.removeAll()
        emptySlotFrames.removeAll()
        clearSwapDrag()
    }

    func shuffle() {
        order.shuffle()
        layout.colGrows.shuffle()
        for ci in layout.boxGrows.indices {
            layout.boxGrows[ci].shuffle()
        }
        rebuildLayout(resetGrows: false)
    }

    /// Alternates on each style shuffle: every second press the border color
    /// matches the background for the "cut" look.
    private var shuffleMatchesColors = false

    /// Which properties the Shuffle button randomizes.
    struct ShuffleOptions {
        var columns = true
        var spacing = true
        var rounding = true
        var borderStyle = true
        var borderThickness = true
        var borderPosition = true
        var color = true
    }
    @Published var shuffleOptions = ShuffleOptions() {
        didSet { saveShuffleOptions() }
    }

    /// Randomizes the enabled properties (see ShuffleOptions).
    func shuffleStyle() {
        let o = shuffleOptions

        if o.spacing { gap = Double(Int.random(in: 10...40)) }
        if o.rounding { cornerRadius = Double(Int.random(in: 0...40)) }
        if o.borderThickness { borderThickness = Double(Int.random(in: 3...24)) }
        if o.borderStyle { borderStyle = BorderStyle.allCases.randomElement() ?? .solid }
        if o.borderPosition { borderPlacement = BorderPlacement.allCases.randomElement() ?? .center }

        if o.color {
            // Soft pastel-leaning random colors to stay in the app's tone
            backgroundColor = Color(hue: .random(in: 0...1),
                                    saturation: .random(in: 0.05...0.45),
                                    brightness: .random(in: 0.85...1.0))
            if shuffleMatchesColors || linkBorderToBackground {
                borderColor = backgroundColor
            } else {
                borderColor = Color(hue: .random(in: 0...1),
                                    saturation: .random(in: 0.15...0.7),
                                    brightness: .random(in: 0.45...1.0))
            }
            shuffleMatchesColors.toggle()
        }

        // Column count + image order + pane proportions
        if o.columns, !images.isEmpty {
            let maxCols = min(5, images.count)
            let minCols = images.count >= 4 ? 2 : 1
            numCols = Int.random(in: minCols...max(minCols, maxCols))
            order.shuffle()
            resetAllImagePositions()
            rebuildLayout(resetGrows: true)
            layout.colGrows = layout.colGrows.map { _ in CGFloat.random(in: 0.7...1.5) }
            layout.boxGrows = layout.boxGrows.map { col in col.map { _ in CGFloat.random(in: 0.7...1.5) } }
        }
        objectWillChange.send()
        // Fade the panel to just the Shuffle button so the new layout is
        // fully visible; restores 2s after the last press.
        beginShuffleFocus()
    }

    /// Resets the visual style to a plain default look.
    /// Whether the Layout settings differ from their defaults.
    var hasStyleChanges: Bool {
        gap != PageStyle().gap || cornerRadius != PageStyle().cornerRadius || borderThickness != 0 || borderStyle != .solid
            || backgroundColor != .white || borderColor != .white || backgroundKind != .color
    }

    func resetStyle() {
        gap = PageStyle().gap
        backgroundColor = .white
        backgroundKind = .color
        cornerRadius = PageStyle().cornerRadius
        resetBorder()
    }

    /// The border back to none (the Border page's reset).
    func resetBorder() {
        borderStyle = .solid
        borderThickness = 0
        borderColor = .white
        borderPlacement = .center
    }

    var hasBorderChanges: Bool {
        borderThickness != 0 || borderStyle != .solid || borderColor != .white || borderPlacement != .center
    }

    /// Empties the canvas for a new collage, which starts from the default
    /// settings (nothing carries over from the last collage) — except the
    /// ratio, which is the one last picked.
    func clear() {
        pages = [CollagePage()]
        currentPageIndex = 0
        selectedOverlayId = nil
        selectedImageId = nil
        forgetRemovedImages()
        useLastRatio()
        imageFrames.removeAll()
        clearSwapDrag()
    }

    // MARK: - Layout

    func rebuildLayout(resetGrows: Bool = false) {
        if resetGrows { layout.resetGrows() }
        layout.rebuild(images: images, order: order, numCols: numCols, strip: currentPage.style.isStrip)
        objectWillChange.send()
    }

    func setRatio(_ r: CanvasRatio) {
        ratio = r
        if r != .custom {
            pictureSize = r.canvasSize(base: 1024)
        }
        resetAllImagePositions()
        rebuildAllPages()
        saveRatio()
    }

    /// The Custom size fields as a canvas, in pixels.
    private var customCanvasSize: CGSize {
        let w = customUnit.toPx(CGFloat(Double(customWidth) ?? 1200))
        let h = customUnit.toPx(CGFloat(Double(customHeight) ?? 900))
        return CGSize(width: max(100, min(6000, w)), height: max(100, min(6000, h)))
    }

    /// Makes the current page `n` pictures wide (1 = a single picture).
    func setSlides(_ n: Int) {
        // No wider than the posts left allow.
        let n = min(max(n, 1), Self.maxSlides, slides + Self.maxPosts - pictureCount)
        guard n != slides else { return }
        let wasStrip = isStrip
        currentPage.style.slides = n
        // Back to one post: Strip goes (it's for spread pages only).
        if n == 1 { currentPage.style.isStrip = false }
        if let f = slideFocus { slideFocus = min(f, n - 1) }
        Diagnostics.log("page \(safePageIndex + 1) \(n) pictures wide · canvas \(Int(canvasSize.width))x\(Int(canvasSize.height))")
        for i in currentPage.images.indices {
            currentPage.images[i].panOffset = .zero
            currentPage.images[i].framedByUser = false
            currentPage.images[i].zoom = 1.0
            currentPage.images[i].rotation = 0
            currentPage.images[i].lastBoxSize = .zero
        }
        rebuildLayout(resetGrows: wasStrip != isStrip)
    }

    /// `slides` slides of `slide` side by side.
    static func stripSize(_ slide: CGSize, slides: Int) -> CGSize {
        CGSize(width: slide.width * CGFloat(max(slides, 1)), height: slide.height)
    }

    func applyCustomSize() {
        pictureSize = customCanvasSize
        ratio = .custom
        resetAllImagePositions()
        rebuildAllPages()
        saveRatio()
    }

    // MARK: - Persistence (ratio + shuffle options)

    private enum DefaultsKey {
        static let customWidth = "customWidth"
        static let customHeight = "customHeight"
        static let customUnit = "customUnit"
        static let shuffle = "shuffleOptions"
        static let lastRatio = "lastRatio"
    }

    /// The ratio a collage starts with until another one is picked.
    static let defaultRatio: CanvasRatio = .portrait916

    /// Gives the (new) collage the ratio last picked, 9:16 at first.
    private func useLastRatio() {
        ratio = CanvasRatio(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.lastRatio) ?? "") ?? Self.defaultRatio
        pictureSize = ratio == .custom ? customCanvasSize : ratio.canvasSize(base: 1024)
    }

    init() {
        restoreSettings()
        observeEffectSources()
        observeSharpness()
        observeHistory()
        #if DEBUG && canImport(UIKit)
        seedDemoImagesIfRequested()
        #endif
    }

    private func restoreSettings() {
        let d = UserDefaults.standard
        // (A new collage starts from the default Layout settings and ratio;
        // a saved one brings its own.)
        d.removeObject(forKey: "lastPageStyle")

        // Shuffle options
        if let raw = d.array(forKey: DefaultsKey.shuffle) as? [Bool], raw.count == 7 {
            shuffleOptions = ShuffleOptions(
                columns: raw[0], spacing: raw[1], rounding: raw[2],
                borderStyle: raw[3], borderThickness: raw[4],
                borderPosition: raw[5], color: raw[6])
        }

        // Ratio
        if let unit = CustomUnit(rawValue: d.string(forKey: DefaultsKey.customUnit) ?? "") {
            customUnit = unit
        }
        if let w = d.string(forKey: DefaultsKey.customWidth) { customWidth = w }
        if let h = d.string(forKey: DefaultsKey.customHeight) { customHeight = h }
        useLastRatio()
    }

    private func saveRatio() {
        let d = UserDefaults.standard
        d.set(customWidth, forKey: DefaultsKey.customWidth)
        d.set(customHeight, forKey: DefaultsKey.customHeight)
        d.set(customUnit.rawValue, forKey: DefaultsKey.customUnit)
        d.set(ratio.rawValue, forKey: DefaultsKey.lastRatio)
    }

    private func saveShuffleOptions() {
        let o = shuffleOptions
        UserDefaults.standard.set(
            [o.columns, o.spacing, o.rounding, o.borderStyle,
             o.borderThickness, o.borderPosition, o.color],
            forKey: DefaultsKey.shuffle)
    }

    func resetAllImagePositions() {
        // On a copy, written back once (each write to the pages redraws).
        var all = pages
        for pi in all.indices {
            for i in all[pi].images.indices {
                all[pi].images[i].panOffset = .zero
                all[pi].images[i].framedByUser = false
                all[pi].images[i].zoom = 1.0
                all[pi].images[i].rotation = 0
                all[pi].images[i].lastBoxSize = .zero
            }
        }
        pages = all
    }

    /// Rebuilds the layout of every page — used when a global setting that
    /// affects arrangement (columns, ratio) changes.
    func rebuildAllPages(resetGrows: Bool = true) {
        for pi in pages.indices {
            if resetGrows { pages[pi].layout.resetGrows() }
            pages[pi].layout.rebuild(images: pages[pi].images,
                                     order: pages[pi].order,
                                     numCols: pages[pi].style.numCols, strip: pages[pi].style.isStrip)
        }
    }

    // MARK: - Pan / Zoom

    /// Pan offsets are stored NORMALIZED to the box size (fractions of box
    /// width/height), so the composition is identical at any render scale —
    /// preview, canvas zoom, and full-resolution export.
    static func normalizedPan(_ pan: CGSize, in boxSize: CGSize) -> CGSize {
        CGSize(width: boxSize.width > 0 ? pan.width / boxSize.width : 0,
               height: boxSize.height > 0 ? pan.height / boxSize.height : 0)
    }

    static func panPixels(_ normalized: CGSize, in boxSize: CGSize) -> CGSize {
        CGSize(width: normalized.width * boxSize.width,
               height: normalized.height * boxSize.height)
    }

    func updatePan(id: UUID, delta: CGSize, boxSize: CGSize) {
        guard let idx = images.firstIndex(where: { $0.id == id }) else { return }
        var img = images[idx]
        let current = Self.panPixels(img.panOffset, in: boxSize)
        let newPan = CGSize(
            width: current.width + delta.width,
            height: current.height + delta.height
        )
        let clamped = clamp(pan: newPan, zoom: img.zoom, boxSize: boxSize, naturalSize: img.naturalSize)
        img.panOffset = Self.normalizedPan(clamped, in: boxSize)
        img.lastBoxSize = boxSize
        img.framedByUser = true
        images[idx] = img
    }

    func setPan(id: UUID, pan normalizedPan: CGSize, boxSize: CGSize) {
        guard let idx = images.firstIndex(where: { $0.id == id }) else { return }
        var img = images[idx]
        let px = Self.panPixels(normalizedPan, in: boxSize)
        let clamped = clamp(pan: px, zoom: img.zoom, boxSize: boxSize, naturalSize: img.naturalSize)
        img.panOffset = Self.focusPan(for: img, boxSize: boxSize) ?? Self.normalizedPan(clamped, in: boxSize)
        img.lastBoxSize = boxSize
        images[idx] = img
    }

    func setBoxSize(id: UUID, boxSize: CGSize) {
        guard !isRenderingOffscreen else { return }
        // Mid splitter drag: noted, written once the drag ends (each write
        // redraws every box, and a text box would re-render every frame).
        if isResizing {
            pendingBoxSizes[id] = boxSize
            return
        }
        guard let idx = images.firstIndex(where: { $0.id == id }),
              boxSize.differs(from: images[idx].lastBoxSize) else { return }
        Diagnostics.count("boxSize")
        // All changes on a copy, written back once: each write to the pages
        // redraws every box.
        var img = images[idx]
        img.lastBoxSize = boxSize
        // A photo not positioned by hand keeps its subject in view.
        if let pan = Self.focusPan(for: img, boxSize: boxSize), pan != img.panOffset {
            img.panOffset = pan
        }
        // A text block always takes the shape of its box: re-render when the
        // box's proportions moved away from the bitmap's.
        if let style = img.textStyle, boxSize.width > 1, boxSize.height > 1 {
            let target = CollageImage.textRenderSize(forBox: boxSize)
            let current = img.naturalSize
            if abs(target.width - current.width) > 2 || abs(target.height - current.height) > 2 {
                img.setImage(CollageImage.renderTextImage(
                    style: style, size: target, boxLongEdge: max(boxSize.width, boxSize.height)))
                img.textStyle = style
            }
        }
        images[idx] = img
    }

    func setZoom(id: UUID, zoom: CGFloat, anchor: CGPoint, boxSize: CGSize) {
        guard let idx = images.firstIndex(where: { $0.id == id }) else { return }
        var img = images[idx]
        let prevZoom = img.zoom
        let newZoom = max(1.0, min(4.0, zoom))
        let ratio = newZoom / prevZoom
        let panPx = Self.panPixels(img.panOffset, in: boxSize)
        let newPan = CGSize(
            width: anchor.x - ratio * (anchor.x - panPx.width),
            height: anchor.y - ratio * (anchor.y - panPx.height)
        )
        img.zoom = newZoom
        img.framedByUser = true
        let clamped = clamp(pan: newPan, zoom: newZoom, boxSize: boxSize, naturalSize: img.naturalSize)
        img.panOffset = Self.normalizedPan(clamped, in: boxSize)
        images[idx] = img
    }

    /// Sets the image's rotation (radians) from a two-finger rotate gesture.
    func setRotation(id: UUID, rotation: CGFloat) {
        guard let idx = images.firstIndex(where: { $0.id == id }) else { return }
        images[idx].rotation = rotation
    }

    /// Commits a completed pinch/rotate gesture: multiplies zoom by the final
    /// scale factor, adds the rotation delta, and re-clamps the pan. Called
    /// once at gesture end (the live transform is rendered locally in the view
    /// so the model isn't churned mid-gesture).
    func commitZoomRotate(id: UUID, scaleFactor: CGFloat, angleDelta: CGFloat, boxSize: CGSize) {
        guard let idx = images.firstIndex(where: { $0.id == id }) else { return }
        var img = images[idx]
        // RotationGesture emits NaN when the fingers nearly coincide, and
        // MagnificationGesture can too — never let it poison the stored
        // transform (rotation += NaN sticks until a manual reset).
        let safeScale = (scaleFactor.isFinite && scaleFactor > 0) ? scaleFactor : 1.0
        let safeAngle = angleDelta.isFinite ? angleDelta : 0
        img.zoom = max(1.0, min(4.0, img.zoom * safeScale))
        img.rotation += safeAngle
        img.framedByUser = true
        if !img.rotation.isFinite { img.rotation = 0 }
        let panPx = Self.panPixels(img.panOffset, in: boxSize)
        let clamped = clamp(pan: panPx, zoom: img.zoom, boxSize: boxSize, naturalSize: img.naturalSize)
        img.panOffset = Self.normalizedPan(clamped, in: boxSize)
        img.lastBoxSize = boxSize
        images[idx] = img
        // The heal-rebuild can recreate the view before its
        // onChange(of: pinching) delivers false — release the zoom lock here
        // so it can never stick.
        endImageZoom(id: id)
    }

    /// New identity for a box view → SwiftUI rebuilds it with fresh gesture
    /// recognizers. Called (deferred) after every pinch ends so recognizer
    /// corruption can never outlive a single gesture.
    func bumpGestureEpoch(id: UUID) {
        guard let idx = images.firstIndex(where: { $0.id == id }) else { return }
        images[idx].gestureEpoch += 1
    }

    func resetTransform(id: UUID) {
        guard let idx = images.firstIndex(where: { $0.id == id }) else { return }
        images[idx].panOffset = .zero
        images[idx].framedByUser = false
        images[idx].zoom = 1.0
        images[idx].rotation = 0
    }

    func clamp(pan: CGSize, zoom: CGFloat, boxSize: CGSize, naturalSize: CGSize) -> CGSize {
        // 1. Calculate the base scale that achieves 'Aspect Fill' (cover)
        let scaleW = boxSize.width / naturalSize.width
        let scaleH = boxSize.height / naturalSize.height
        let coverScale = max(scaleW, scaleH) * zoom
        
        // 2. Compute the actual rendered width and height in box-space coordinates
        let renderedWidth = naturalSize.width * coverScale
        let renderedHeight = naturalSize.height * coverScale
        
        // 3. Determine the maximum allowable pan offsets.
        // Since the image is centered at zero, the maximum distance it can slide
        // left/right or up/down is half of the total overflow.
        let maxPanX = max(0, (renderedWidth - boxSize.width) / 2.0)
        let maxPanY = max(0, (renderedHeight - boxSize.height) / 2.0)
        
        // 4. Bound the requested pan between negative and positive maximum limits
        let clampedWidth = max(-maxPanX, min(maxPanX, pan.width))
        let clampedHeight = max(-maxPanY, min(maxPanY, pan.height))
        
        return CGSize(width: clampedWidth, height: clampedHeight)
    }

    // MARK: - Splitter resize
    @Published var isResizing = false
    private var dragStartBoxGrows: [[CGFloat]] = []
    private var dragStartColGrows: [CGFloat] = []

    func beginResize() {
        isResizing = true
        dragStartBoxGrows = layout.boxGrows
        dragStartColGrows = layout.colGrows
    }

    func endResize() {
        isResizing = false
        applyPendingBoxSizes()
    }

    /// Box sizes reported during a splitter drag.
    private var pendingBoxSizes: [UUID: CGSize] = [:]

    private func applyPendingBoxSizes() {
        let pending = pendingBoxSizes
        pendingBoxSizes = [:]
        for (id, size) in pending { setBoxSize(id: id, boxSize: size) }
    }

    func updateResizeBoxes(colIndex: Int, biA: Int, biB: Int, totalDeltaFraction: CGFloat) {
        // The layout may have changed since the drag began.
        guard dragStartBoxGrows.indices.contains(colIndex), layout.boxGrows.indices.contains(colIndex),
              dragStartBoxGrows[colIndex].count == layout.boxGrows[colIndex].count,
              dragStartBoxGrows[colIndex].indices.contains(biA),
              dragStartBoxGrows[colIndex].indices.contains(biB) else { return }
        var columnBoxes = dragStartBoxGrows[colIndex]
        let total = columnBoxes.reduce(0, +)
        if total == 0 { return }
        
        let sumAB = dragStartBoxGrows[colIndex][biA] + dragStartBoxGrows[colIndex][biB]
        let deltaAmount = totalDeltaFraction * total
        
        let minGrow = total * 0.05
        let newA = max(minGrow, min(sumAB - minGrow, dragStartBoxGrows[colIndex][biA] + deltaAmount))
        let newB = sumAB - newA
        
        columnBoxes[biA] = newA
        columnBoxes[biB] = newB
        
        layout.boxGrows[colIndex] = columnBoxes
        objectWillChange.send()
    }

    func updateResizeCols(ciA: Int, ciB: Int, totalDeltaFraction: CGFloat) {
        guard ciA >= 0, ciB >= 0, ciA < dragStartColGrows.count, ciB < dragStartColGrows.count,
              dragStartColGrows.count == layout.colGrows.count else { return }
        
        let totalSum = dragStartColGrows.reduce(0, +)
        let sumAB = dragStartColGrows[ciA] + dragStartColGrows[ciB]
        if totalSum == 0 { return }
        
        let deltaAmount = totalDeltaFraction * totalSum
        let minGrow = totalSum * 0.05
        
        let newA = max(minGrow, min(sumAB - minGrow, dragStartColGrows[ciA] + deltaAmount))
        let newB = sumAB - newA
        
        layout.colGrows[ciA] = newA
        layout.colGrows[ciB] = newB
        
        objectWillChange.send()
    }

    func resizeBoxes(colIndex: Int, biA: Int, biB: Int, deltaFraction: CGFloat) {
        guard layout.boxGrows.indices.contains(colIndex),
              layout.boxGrows[colIndex].indices.contains(biA),
              layout.boxGrows[colIndex].indices.contains(biB) else { return }
        var columnBoxes = layout.boxGrows[colIndex]
        let total = columnBoxes.reduce(0, +)
        if total == 0 { return }
        
        let sumAB = columnBoxes[biA] + columnBoxes[biB]
        let deltaAmount = deltaFraction * total
        
        let minGrow = total * 0.05
        let newA = max(minGrow, min(sumAB - minGrow, columnBoxes[biA] + deltaAmount))
        let newB = sumAB - newA
        
        columnBoxes[biA] = newA
        columnBoxes[biB] = newB
        
        layout.boxGrows[colIndex] = columnBoxes
        objectWillChange.send()
    }

    func resizeCols(ciA: Int, ciB: Int, deltaFraction: CGFloat) {
        guard ciA >= 0, ciB >= 0, ciA < layout.colGrows.count, ciB < layout.colGrows.count else { return }
        
        let totalSum = layout.colGrows.reduce(0, +)
        let sumAB = layout.colGrows[ciA] + layout.colGrows[ciB]
        if totalSum == 0 { return }
        
        let deltaAmount = deltaFraction * totalSum
        let minGrow = totalSum * 0.05
        
        let newA = max(minGrow, min(sumAB - minGrow, layout.colGrows[ciA] + deltaAmount))
        let newB = sumAB - newA
        
        layout.colGrows[ciA] = newA
        layout.colGrows[ciB] = newB
        
        objectWillChange.send()
    }

    // MARK: - Swap

    func swapImages(id1: UUID, id2: UUID) {
        guard let i1 = order.firstIndex(of: id1),
              let i2 = order.firstIndex(of: id2) else {
            // Target wasn't a real image on this page (e.g. a stale frame) —
            // never leave the swap drag stuck.
            clearSwapDrag()
            return
        }
        order.swapAt(i1, i2)
        // Swap the two boxes in the built layout rather than re-flowing it,
        // so an arrangement made by inserting images stays put.
        var l = layout
        if let a = l.position(of: id1), let b = l.position(of: id2) {
            let itemA = l.columns[a.col][a.row]
            l.columns[a.col][a.row] = l.columns[b.col][b.row]
            l.columns[b.col][b.row] = itemA
            layout = l
        } else {
            rebuildLayout(resetGrows: false)
        }
        // Keep zoom and rotation across the swap — zoom is stored relative to
        // the box's aspect-fill cover, so it re-fits the new box automatically
        // (never leaves gaps). Only the pan resets: it's normalized to the old
        // box's geometry and rarely means the same thing in the new one.
        resetPan(id: id1)
        resetPan(id: id2)
        clearSwapDrag()
        objectWillChange.send()
    }

    /// Swaps two photos on any page (the Images tab's page rows): their
    /// places in the order and their boxes in the layout, like a swap on
    /// the canvas.
    func swapImages(onPage pi: Int, _ id1: UUID, _ id2: UUID) {
        guard pages.indices.contains(pi), id1 != id2,
              let i1 = pages[pi].order.firstIndex(of: id1),
              let i2 = pages[pi].order.firstIndex(of: id2) else { return }
        var page = pages[pi]
        page.order.swapAt(i1, i2)
        if let a = page.layout.position(of: id1), let b = page.layout.position(of: id2) {
            let itemA = page.layout.columns[a.col][a.row]
            page.layout.columns[a.col][a.row] = page.layout.columns[b.col][b.row]
            page.layout.columns[b.col][b.row] = itemA
        } else {
            page.layout.rebuild(images: page.images, order: page.order, numCols: page.style.numCols, strip: page.style.isStrip)
        }
        // As on the canvas: zoom and rotation stay, the pan starts over.
        for id in [id1, id2] {
            if let k = page.images.firstIndex(where: { $0.id == id }) {
                page.images[k].panOffset = .zero
                page.images[k].framedByUser = false
                page.images[k].lastBoxSize = .zero
            }
        }
        pages[pi] = page
    }

    /// Clears just the pan composition, preserving zoom and rotation.
    private func resetPan(id: UUID) {
        guard let idx = images.firstIndex(where: { $0.id == id }) else { return }
        images[idx].panOffset = .zero
        images[idx].framedByUser = false
        images[idx].lastBoxSize = .zero
    }

    func updateImageFrame(id: UUID, frame: CGRect) {
        // Offscreen renders (effect snapshot, export) lay out at canvas
        // scale — their geometry must not replace the on-screen one.
        guard !isRenderingOffscreen else { return }
        imageFrames[id] = frame
    }

    func beginSwapHold(id: UUID) {
        guard imageZoomingId == nil, !isCanvasZooming else { return }
        swapArmedId = id
        draggingId = nil
        dropTargetId = nil
        dragOffset = .zero
    }

    func beginSwapDrag(id: UUID) {
        guard imageZoomingId == nil, !isCanvasZooming else { return }
        swapArmedId = id
        draggingId = id
        dropTargetId = nil
        dragOffset = .zero
    }

    func updateSwapDrag(location: CGPoint, translation: CGSize, excluding sourceId: UUID) {
        draggingId = sourceId
        dragOffset = translation
        // A splitter wins over the images it borders.
        let insert = insertTarget(at: location, excluding: sourceId)
        if dropInsertTarget != insert { dropInsertTarget = insert }
        dropTargetId = insert == nil ? swapTargetId(at: location, excluding: sourceId) : nil
        dropTargetEmptyCol = insert == nil && dropTargetId == nil ? emptySlotTarget(at: location) : nil
    }

    func finishSwapDrag(sourceId: UUID, location: CGPoint) {
        if let insert = insertTarget(at: location, excluding: sourceId) {
            insertImage(id: sourceId, at: insert)
        } else if let targetId = swapTargetId(at: location, excluding: sourceId) {
            swapImages(id1: sourceId, id2: targetId)
        } else if let col = emptySlotTarget(at: location) {
            moveImageToEmptyColumn(id: sourceId, columnIndex: col)
        } else {
            clearSwapDrag()
        }
        // Safety net: whatever path ran, never leave a drag stuck.
        if draggingId != nil { clearSwapDrag() }
        // Re-read every box once the rearrange animation has settled.
        refreshTrackedGeometry(after: 0.45)
    }

    func clearSwapDrag() {
        // Only what's set: an unchanged write still redraws everything.
        if swapArmedId != nil { swapArmedId = nil }
        if draggingId != nil { draggingId = nil }
        if dropTargetId != nil { dropTargetId = nil }
        if dropTargetEmptyCol != nil { dropTargetEmptyCol = nil }
        if dropInsertTarget != nil { dropInsertTarget = nil }
        if dragOffset != .zero { dragOffset = .zero }
    }

    /// Belt-and-braces reset of every transient interaction flag. If any
    /// gesture were ever cancelled without its `onEnded` firing, these could
    /// stick and lock out input — calling this guarantees a clean slate so
    /// the page can never stay frozen.
    func clearInteractionLocks() {
        clearSwapDrag()
        if imageZoomingId != nil { imageZoomingId = nil }
        if isCanvasZooming { isCanvasZooming = false }
        // A splitter drag cancelled without its end would otherwise keep
        // undo and autosave paused.
        if isResizing {
            isResizing = false
            applyPendingBoxSizes()
        }
    }

    /// Lets go of whatever pointed at a picture that's no longer in the
    /// collage (selection, editors, caches).
    func forgetRemovedImages() {
        let ids = Set(pages.flatMap { $0.images.map(\.id) })
        if let id = selectedImageId, !ids.contains(id) { selectedImageId = nil }
        if let id = textEditTargetId, !ids.contains(id) { textEditTargetId = nil }
        if let id = protrusionTargetId, !ids.contains(id) { protrusionTargetId = nil }
        if let id = photoEditTargetId, !ids.contains(id) { photoEditTargetId = nil }
        if let id = boxActionTargetId, !ids.contains(id), !showReplacePicker { boxActionTargetId = nil }
        if gradedProxies.keys.contains(where: { !ids.contains($0) }) {
            gradedProxies = gradedProxies.filter { ids.contains($0.key) }
        }
        if subjectMasks.keys.contains(where: { !ids.contains($0) }) {
            subjectMasks = subjectMasks.filter { ids.contains($0.key) }
        }
        focusChecked = focusChecked.filter { ids.contains($0) }
        mergedShapes = mergedShapes.filter { ids.contains($0.key) }
        instanceOutlines = instanceOutlines.filter { ids.contains($0.key) }
        dilatedMasks = dilatedMasks.filter { ids.contains($0.key) }
        subjectOutlines = subjectOutlines.filter { ids.contains($0.key) }
    }

    func emptySlotTarget(at location: CGPoint) -> Int? {
        emptySlotFrames.first { _, frame in frame.contains(location) }?.key
    }

    /// Moves an image of the current page into an empty column, so images can
    /// be repositioned around empty slots. Mutates the built layout directly;
    /// the placement lasts until the layout is rebuilt (columns change,
    /// add/remove, shuffle).
    func moveImageToEmptyColumn(id: UUID, columnIndex: Int) {
        var l = layout
        guard l.columns.indices.contains(columnIndex),
              l.columns[columnIndex].isEmpty,
              let srcCol = l.columns.firstIndex(where: { $0.contains { $0.imageId == id } }),
              let srcIdx = l.columns[srcCol].firstIndex(where: { $0.imageId == id }) else {
            clearSwapDrag()
            return
        }

        let item = l.columns[srcCol].remove(at: srcIdx)
        if srcCol < l.boxGrows.count, srcIdx < l.boxGrows[srcCol].count {
            l.boxGrows[srcCol].remove(at: srcIdx)
        }
        l.columns[columnIndex] = [item]
        if columnIndex < l.boxGrows.count {
            l.boxGrows[columnIndex] = [1.0]
        }
        layout = l
        // Same policy as swapImages: zoom/rotation survive the move.
        resetPan(id: id)
        clearSwapDrag()
    }

    func imageFrame(for id: UUID) -> CGRect? {
        imageFrames[id]
    }

    /// The splitter under `location`: a gap between two boxes in a column,
    /// or the top / bottom end of a column. Each zone is at least
    /// `insertZoneHeight` tall, so it's easy to hit even with no spacing.
    /// Gaps right next to the dragged image are skipped (dropping there
    /// would change nothing).
    func insertTarget(at location: CGPoint, excluding sourceId: UUID) -> InsertTarget? {
        // Worked out for columns; with rows, everything is transposed in and
        // the zone transposed back out.
        func t(_ r: CGRect) -> CGRect { isRows ? CGRect(x: r.minY, y: r.minX, width: r.height, height: r.width) : r }
        let location = isRows ? CGPoint(x: location.y, y: location.x) : location
        let insertZoneHeight: CGFloat = 28
        let source = layout.position(of: sourceId)
        for (ci, column) in layout.columns.enumerated() {
            let frames = column.compactMap { imageFrames[$0.imageId] }.map(t)
            guard frames.count == column.count, !frames.isEmpty else { continue }
            for index in 0...column.count {
                if let source, source.col == ci, index == source.row || index == source.row + 1 { continue }
                // The edges of the boxes above and below this position.
                let above = index > 0 ? frames[index - 1] : nil
                let below = index < frames.count ? frames[index] : nil
                let top = above?.maxY ?? below!.minY
                let bottom = below?.minY ?? above!.maxY
                let minX = min(above?.minX ?? .infinity, below?.minX ?? .infinity)
                let maxX = max(above?.maxX ?? -.infinity, below?.maxX ?? -.infinity)
                let midY = (top + bottom) / 2
                let height = max(bottom - top, insertZoneHeight)
                let zone = CGRect(x: minX, y: midY - height / 2, width: maxX - minX, height: height)
                if zone.contains(location) {
                    return InsertTarget(column: ci, index: index, frame: t(zone))
                }
            }
        }
        return nil
    }

    /// Moves an image to a new spot in the built layout — any column, any
    /// position — so columns can hold different numbers of images (e.g. 3
    /// and 1). The column it leaves and the one it joins get equal heights
    /// per box. Lasts until the layout is re-flowed (column count changes,
    /// images added or removed, shuffle).
    func insertImage(id: UUID, at target: InsertTarget) {
        var l = layout
        guard let src = l.position(of: id), l.columns.indices.contains(target.column) else {
            clearSwapDrag()
            return
        }
        let item = l.columns[src.col].remove(at: src.row)
        var index = target.index
        if src.col == target.column && src.row < index { index -= 1 }
        l.columns[target.column].insert(item, at: min(index, l.columns[target.column].count))
        for ci in Set([src.col, target.column]) where ci < l.boxGrows.count {
            let n = l.columns[ci].count
            l.boxGrows[ci] = Array(repeating: n > 0 ? 1.0 / CGFloat(n) : 0, count: n)
        }
        layout = l
        // Same policy as swapImages: zoom/rotation survive the move.
        resetPan(id: id)
        clearSwapDrag()
        objectWillChange.send()
    }

    func swapTargetId(at location: CGPoint, excluding sourceId: UUID) -> UUID? {
        // Only images on the current page are valid targets — ignore stale
        // frames left over from other pages (e.g. during a page transition).
        let onPage = Set(order)
        return imageFrames.first { id, frame in
            id != sourceId && onPage.contains(id) && frame.contains(location)
        }?.key
    }

    func beginCanvasZoom() -> Bool {
        guard imageZoomingId == nil else { return false }
        isCanvasZooming = true
        clearSwapDrag()
        return true
    }

    func endCanvasZoom() {
        isCanvasZooming = false
    }

    func beginImageZoom(id: UUID) -> Bool {
        guard !isCanvasZooming else { return false }
        imageZoomingId = id
        clearSwapDrag()
        restartZoomWatchdog(id: id)
        return true
    }

    func endImageZoom(id: UUID) {
        if imageZoomingId == id {
            imageZoomingId = nil
        }
        if zoomWatchdogId == id {
            zoomWatchdog?.cancel()
            zoomWatchdogId = nil
        }
    }

    // MARK: Pinch watchdog
    // A two-finger recognizer can wedge mid-gesture: it stops getting touches
    // but never delivers end/cancel, so the box's @GestureState sticks and the
    // box goes deaf (observed live: "pinch begin" with no end ever following).
    // Every pinch event feeds this watchdog; if a pinch goes silent without
    // ending, the box view is rebuilt — destroying the wedged recognizer.

    private var zoomWatchdog: Task<Void, Never>? = nil
    private var zoomWatchdogId: UUID? = nil

    /// Called on every pinch update so an active, moving gesture never trips
    /// the watchdog. (A perfectly motionless two-finger hold produces no
    /// events; 2s of that is rare, and the heal is invisible at rest.)
    func noteZoomActivity(id: UUID) {
        restartZoomWatchdog(id: id)
    }

    private func restartZoomWatchdog(id: UUID) {
        zoomWatchdog?.cancel()
        zoomWatchdogId = id
        zoomWatchdog = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            if imageZoomingId == id { imageZoomingId = nil }
            zoomWatchdogId = nil
            bumpGestureEpoch(id: id)
        }
    }

    // MARK: - Export

    /// Exports the current page, or all non-empty pages, at the chosen size
    /// and format, numbered in order, then presents the share sheet.
    /// Where an export goes: the share sheet, or straight into Photos.
    enum ExportDestination { case share, photos }

    func exportPages(allPages: Bool, settings: ExportSettings = .saved, to destination: ExportDestination = .share) async {
        guard hasAnyImages, !isExporting else { return }
        exportCancelRequested = false
        Diagnostics.log("export \(allPages ? "all pages" : "page") \(settings.size.rawValue) \(settings.format.rawValue)")
        // Saved first: no save runs while exporting (the page on screen is
        // the one being exported).
        saveProjectNow()
        isExporting = true
        isBusy = true
        isLoading = true
        showExportSheet = false
        savePhase = .saving
        // Let the "Exporting" dialog animate in before the render blocks the main thread
        try? await Task.sleep(nanoseconds: 350_000_000)

        let originalIndex = currentPageIndex

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CollageExport", isDirectory: true)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let targets = allPages
            ? pages.indices.filter { !pages[$0].images.isEmpty }
            : [safePageIndex]

        exportTotalPages = targets.count
        exportProgress = 0

        var urls: [URL] = []
        var failed: [Int] = []
        // A wide page goes out as one picture per slide, numbered straight
        // through with the other pages' pictures.
        let pictures = targets.reduce(0) { $0 + min(max(pages[$1].style.slides, 1), Self.maxSlides) }
        for (n, pi) in targets.enumerated() {
            if exportCancelRequested { break }
            currentPageIndex = pi
            let slideCount = slides
            let scale = settings.scale(for: pictureSize)
            await prepareExportPage(scale: scale)
            refreshEffectMaps(force: true)
            defer {
                // Each page's photos go before the next.
                gradeExportCache = [:]
                exportSources = [:]
                exportProgress = Double(n + 1) / Double(targets.count)
            }
            for slide in 0..<slideCount {
                if exportCancelRequested { break }
                #if DEBUG && canImport(UIKit)
                // `-uiTestSlowExport`: time to press Cancel.
                if UITest.slowExport { try? await Task.sleep(nanoseconds: 1_500_000_000) }
                if exportCancelRequested { break }
                #endif
                // Drained per picture: the render and its encoding are big.
                let data: Data? = autoreleasepool {
                    renderCurrentPage(scale: scale, slide: slideCount > 1 ? slide : nil)
                        .flatMap { settings.encode($0) }
                }
                guard let data else {
                    if failed.last != pi + 1 { failed.append(pi + 1) }
                    continue
                }
                // Numbered in order (of the pictures that made it), so a
                // carousel posts in the right sequence.
                let name = pictures > 1 ? String(format: "Collage %02d", urls.count + 1) : "Collage"
                let url = dir.appendingPathComponent(name + "." + settings.format.fileExtension)
                do {
                    try data.write(to: url)
                    urls.append(url)
                } catch {
                    if failed.last != pi + 1 { failed.append(pi + 1) }
                }
                if slideCount > 1 {
                    exportProgress = (Double(n) + Double(slide + 1) / Double(slideCount)) / Double(targets.count)
                }
                // Let the progress bar repaint between pictures.
                await Task.yield()
            }
        }

        currentPageIndex = originalIndex
        gradeExportCache = [:]
        exportSources = [:]
        isExporting = false
        isBusy = false
        isLoading = false
        savePhase = .idle
        if exportCancelRequested {
            Diagnostics.log("export cancelled")
            exportCancelRequested = false
            try? FileManager.default.removeItem(at: dir)
            return
        }
        var problem: String?
        if !failed.isEmpty {
            Diagnostics.log("export failed for pages \(failed)")
            problem = urls.isEmpty
                ? "The collage couldn't be exported. Try a smaller size, or close other apps and try again."
                : "Page\(failed.count == 1 ? "" : "s") \(failed.map(String.init).joined(separator: ", ")) couldn't be exported; the others are \(destination == .photos ? "saved" : "ready to share")."
        }
        guard !urls.isEmpty else {
            exportProblem = problem
            return
        }
        switch destination {
        case .share:
            exportedFiles = urls
            exportProblemAfterSheet = problem
            showExportSheet = true
        case .photos:
            let saved = await PhotoLibrarySaver.save(urls)
            try? FileManager.default.removeItem(at: dir)
            switch saved {
            case .saved(let n):
                #if DEBUG && canImport(UIKit)
                UITest.savedToPhotos += n
                #endif
                flashToast(n == 1 ? "Saved to Photos" : "Saved \(n) posts to Photos", icon: "checkmark.circle.fill")
                exportProblem = problem
            case .denied:
                exportProblem = "das Kolaž isn't allowed to add photos. Allow it in Settings › Privacy & Security › Photos, or use Share instead."
            case .failed:
                exportProblem = "The pictures couldn't be saved to Photos. Try Share instead."
            }
        }
    }

    /// The share sheet closed: the exported files (tens of MB) go.
    func clearExportFiles() {
        guard !isExporting else { return }
        exportedFiles = []
        if let problem = exportProblemAfterSheet {
            exportProblemAfterSheet = nil
            // After the sheet has gone.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.exportProblem = problem }
        }
        try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory
            .appendingPathComponent("CollageExport", isDirectory: true))
    }

    /// Before a page is drawn for export: each photo scaled to the pixels it
    /// fills at the export size (never the whole 4096 px original when the
    /// box is small) and graded, one photo at a time off the main thread,
    /// so the render itself only draws.
    private func prepareExportPage(scale: CGFloat) async {
        let rects = layout.rects(canvasSize: canvasSize, gap: CGFloat(gap), rows: isRows)
        for img in currentPage.images where !img.isPlaceholder && !img.isText {
            let box = rects[img.id]?.size ?? canvasSize
            let placement = ImagePlacement.compute(natural: img.naturalSize, boxSize: box, zoom: img.zoom,
                                                   rotation: img.rotation, pan: .zero)
            let drawn = placement.map { max($0.size.width, $0.size.height) } ?? max(canvasSize.width, canvasSize.height)
            let edge = ceil(drawn * scale * 1.05)
            let original = img.original, grade = grade(for: img)
            let (source, graded): (PlatformImage, PlatformImage?) = await Task.detached(priority: .userInitiated) {
                autoreleasepool {
                    // Decoded straight at that size from the compressed original.
                    let source = original.scaled(maxEdge: edge)
                    return (source, grade.isIdentity ? nil : ContentGrader.apply(grade, to: source))
                }
            }.value
            exportSources[img.id] = source
            if let graded { gradeExportCache[img.id] = Graded(source: source, grade: grade, image: graded) }
        }
    }

    /// Snapshots the currently selected page at full canvas resolution using
    /// SwiftUI's `ImageRenderer`. This renders the view tree in isolation
    /// (no window / hosting controller needed), which is both the supported
    /// way to rasterize a SwiftUI view and free of the offscreen
    /// `drawHierarchy(afterScreenUpdates:)` crash.
    @MainActor
    private func renderCurrentPage(scale: CGFloat = 2, slide: Int? = nil) -> PlatformImage? {
        // One slide: the whole canvas laid out as on screen, shifted and
        // cut to that slide — so neighbouring slides meet exactly.
        let size = slide == nil ? canvasSize : pictureSize
        let gridView = CollageGridView_Grid(scale: 1.0)
            .frame(width: canvasSize.width, height: canvasSize.height)
            .environmentObject(self)
            .offset(x: -CGFloat(slide ?? 0) * pictureSize.width)
            .frame(width: size.width, height: size.height, alignment: .leading)
            .clipped()

        let renderer = ImageRenderer(content: gridView)
        renderer.proposedSize = ProposedViewSize(size)
        // Standard: 2× the 1024-pt canvas → crisp while staying memory-safe.
        renderer.scale = scale
        renderer.isOpaque = false

        // The export's prepared pictures (see prepareExportPage), for this
        // render only.
        renderFullResolution = true
        defer { renderFullResolution = false }
        #if canImport(UIKit)
        return renderer.uiImage
        #else
        return renderer.nsImage
        #endif
    }

}
