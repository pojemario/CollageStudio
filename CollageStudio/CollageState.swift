import SwiftUI

@MainActor
class CollageState: ObservableObject {

    // MARK: - Pages
    static let maxImagesPerPage = 15
    static let maxPages = 20

    @Published var pages: [CollagePage] = [CollagePage()]
    /// Edge the incoming page slides in from — set from the navigation
    /// direction so the canvas page transition matches finger movement.
    var pageSlideEdge: Edge = .trailing

    @Published var currentPageIndex: Int = 0 {
        didSet {
            pageSlideEdge = currentPageIndex > oldValue ? .trailing : .leading
            // Tracked box frames belong to the previous page's boxes
            imageFrames.removeAll()
            emptySlotFrames.removeAll()
            clearSwapDrag()
        }
    }

    private var safePageIndex: Int {
        min(max(currentPageIndex, 0), pages.count - 1)
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
    @Published var canvasSize: CGSize = CGSize(width: 1024, height: 1024)
    @Published var customWidth: String = "1200"
    @Published var customHeight: String = "900"
    @Published var customUnit: CustomUnit = .px

    // MARK: - Layout (stored per page in PageStyle)
    var numCols: Int {
        get { currentPage.style.numCols }
        set { currentPage.style.numCols = newValue }
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

    /// Label of the slider currently being dragged. While set, the panel
    /// fades everything except that slider so the canvas stays visible.
    @Published var activeAdjustment: String? = nil

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
            pages[pi].style = source
            // Columns may have changed, so rebuild that page's layout
            pages[pi].layout.resetGrows()
            pages[pi].layout.rebuild(images: pages[pi].images,
                                     order: pages[pi].order,
                                     numCols: source.numCols)
        }
        lastAppliedStyle = source
    }

    // MARK: - Canvas margin & frame
    /// Extra inset (in canvas pixels) the user adds on top of the frame's
    /// built-in minimum margins. 0 means "just the frame's own margins".
    @Published var canvasMargin: Double = 0
    /// Rotation of the collage grid within the canvas, in degrees.
    @Published var canvasRotation: Double = 0
    /// The selected decorative frame set, or nil for no frame.
    @Published var canvasFrame: CanvasFrameSet? = nil

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

    /// Asset name of the frame variant used for the current ratio.
    private func resolvedFrameAssetName() -> (name: String, isSquareFallback: Bool)? {
        guard let set = canvasFrame else { return nil }
        let suffix = ratio.rawValue.replacingOccurrences(of: ":", with: "x")
        if let name = set.assetName(ratioSuffix: suffix), PlatformImage.named(name) != nil {
            return (name, false)
        }
        if let name = set.assetName(ratioSuffix: "1x1"), PlatformImage.named(name) != nil {
            return (name, true)
        }
        return nil
    }

    /// Minimum content margins of the frame variant in use — margins can
    /// differ per ratio (zero without a frame).
    var frameBaseMargins: (left: CGFloat, top: CGFloat, right: CGFloat, bottom: CGFloat) {
        guard let (name, _) = resolvedFrameAssetName() else { return (0, 0, 0, 0) }
        return CanvasFrameSet.margins(fromAssetName: name)
    }

    /// Frame image for the current canvas ratio. Falls back to the square
    /// 1:1 variant when the exact ratio isn't bundled.
    func resolvedFrame() -> (image: PlatformImage, isSquareFallback: Bool)? {
        guard let (name, isFallback) = resolvedFrameAssetName(),
              let image = PlatformImage.named(name) else { return nil }
        return (image, isFallback)
    }

    // MARK: - Drag to swap
    @Published var swapArmedId: UUID? = nil
    @Published var draggingId: UUID? = nil
    @Published var dropTargetId: UUID? = nil
    /// Empty column currently hovered during a swap drag.
    @Published var dropTargetEmptyCol: Int? = nil
    @Published var dragOffset: CGSize = .zero
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
    /// Live drag translation while the user is pulling the panel (+ = down).
    @Published var panelDrag: CGFloat = 0
    /// True while a pull is in progress.
    @Published var isPanelDragging: Bool = false

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
    func collapsePanel() {
        guard isPanelOpen else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            isPanelOpen = false
            panelDrag = 0
            isPanelDragging = false
        }
    }

    // MARK: - Box actions (long press: replace / delete)
    @Published var boxActionTargetId: UUID? = nil
    @Published var showBoxActionMenu: Bool = false
    @Published var showReplacePicker: Bool = false

    // MARK: - Shared import (Share Extension)
    @Published var pendingSharedImages: [PlatformImage] = []
    @Published var showSharedImportChoice: Bool = false

    // MARK: - Export
    /// While true, image boxes draw the full-resolution originals instead of
    /// the canvas proxies. Only enabled during export rendering.
    @Published var renderFullResolution: Bool = false
    @Published var isExporting: Bool = false
    /// 0…1 progress of a multi-page export (pages rendered / total).
    @Published var exportProgress: Double = 0
    @Published var exportTotalPages: Int = 0

    /// Drives the "Exporting" dialog shown while exporting.
    enum SavePhase: Equatable {
        case idle, saving
    }
    @Published var savePhase: SavePhase = .idle
    /// PNG files written by the last export, named 001.png … 00N.png.
    @Published var exportedFiles: [URL] = []
    @Published var showExportSheet: Bool = false
    /// Asks the user whether to export the current page or all pages.
    @Published var showExportOptions: Bool = false

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

    /// Adds images whose proxies were already generated off the main thread.
    /// Fills the current page up to the per-page limit, then spills into new
    /// pages (up to the page limit; any excess beyond that is dropped).
    /// Target images per page when auto-distributing a fresh batch.
    static let defaultImagesPerPage = 5

    func addPreparedImages(_ prepared: [CollageImage]) {
        let wasEmpty = pages.allSatisfy { $0.images.isEmpty }

        // Fresh collage: spread the batch across auto-created pages at
        // ~5 images per page, each laid out as a balanced grid.
        if wasEmpty {
            let neededPages = Int((Double(prepared.count) / Double(Self.defaultImagesPerPage)).rounded(.up))
            let target = max(pages.count, max(1, neededPages))
            distributeEvenly(prepared, intoPages: target)
            withAnimation(.easeInOut(duration: 0.25)) { isPanelOpen = true }
            return
        }

        var remaining = prepared[...]
        var pi = safePageIndex

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
                                         numCols: pages[pi].style.numCols)
                remaining = remaining.dropFirst(chunk.count)
            }
            guard !remaining.isEmpty else { break }
            guard pages.count < Self.maxPages else { break }
            // Spill pages inherit the style of the page being filled
            pages.append(CollagePage(style: pages[pi].style))
            pi = pages.count - 1
        }

        // First images just arrived: reveal the options panel
        if wasEmpty && !pages.allSatisfy({ $0.images.isEmpty }) {
            withAnimation(.easeInOut(duration: 0.25)) {
                isPanelOpen = true
            }
        }
    }

    /// Resolves the pending Share Extension import once the user has chosen
    /// whether to start a fresh collage or append to the current one.
    func importPendingShared(replacingCurrent: Bool) {
        let shared = pendingSharedImages
        pendingSharedImages = []
        guard !shared.isEmpty else { return }
        if replacingCurrent {
            clear()
        }
        addImages(shared)
    }

    /// Adds the pending shared photos to the existing collage on a fresh page
    /// appended at the end, and navigates to it. Overflow beyond the per-page
    /// limit spills onto further new pages, like a normal import.
    func importPendingSharedAsNewPage() {
        let shared = pendingSharedImages
        pendingSharedImages = []
        guard !shared.isEmpty, pages.count < Self.maxPages else { return }
        pages.append(CollagePage(style: currentPage.style))
        currentPageIndex = pages.count - 1
        addImages(shared)
    }

    /// Spreads the current images plus the pending shared photos evenly
    /// across the defined pages.
    func importPendingSharedBurst() {
        let shared = pendingSharedImages
        pendingSharedImages = []
        guard !shared.isEmpty else { return }
        let all = pages.flatMap { $0.images } + shared.map { CollageImage(image: $0) }
        // Create enough pages for ~4 images each, but never fewer than the
        // pages that already exist.
        let target = max(pages.count, Int((Double(all.count) / 4).rounded(.up)))
        distributeEvenly(all, intoPages: target)
    }

    func discardPendingShared() {
        pendingSharedImages = []
    }

    /// Replaces the image content of an existing box, keeping its position in
    /// the layout. Pan/zoom reset because they are meaningless for the new image.
    func replaceImage(id: UUID, with newImage: PlatformImage) {
        guard let pi = pageIndex(containing: id),
              let idx = pages[pi].images.firstIndex(where: { $0.id == id }) else { return }
        pages[pi].images[idx].setImage(newImage)
        pages[pi].images[idx].panOffset = .zero
        pages[pi].images[idx].zoom = 1.0
        pages[pi].images[idx].lastBoxSize = .zero
        // Rebuild so the layout picks up the new image's aspect ratio,
        // without resetting the user's box/column sizing.
        pages[pi].layout.rebuild(images: pages[pi].images,
                                 order: pages[pi].order,
                                 numCols: pages[pi].style.numCols)
    }

    func removeImage(id: UUID) {
        guard let pi = pageIndex(containing: id) else { return }
        pages[pi].images.removeAll { $0.id == id }
        pages[pi].order.removeAll { $0 == id }
        pages[pi].layout.resetGrows()
        pages[pi].layout.rebuild(images: pages[pi].images,
                                 order: pages[pi].order,
                                 numCols: pages[pi].style.numCols)
        imageFrames.removeValue(forKey: id)
        if draggingId == id || dropTargetId == id {
            clearSwapDrag()
        }
    }

    // MARK: - Page management

    func pageIndex(containing id: UUID) -> Int? {
        pages.firstIndex { $0.images.contains { $0.id == id } }
    }

    func addPage() {
        guard pages.count < Self.maxPages else { return }
        // New pages start with the current page's style
        pages.append(CollagePage(style: currentPage.style))
        currentPageIndex = pages.count - 1
    }

    func deletePage(at index: Int) {
        guard pages.count > 1, pages.indices.contains(index) else { return }
        for img in pages[index].images {
            imageFrames.removeValue(forKey: img.id)
        }
        pages.remove(at: index)
        currentPageIndex = min(currentPageIndex, pages.count - 1)
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
                                     numCols: pages[pi].style.numCols)
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
        guard pages.count < Self.maxPages else { return }
        pages.append(CollagePage(style: currentPage.style))
        moveImage(id: id, toPage: pages.count - 1)
    }

    /// Collapses the whole collage onto a single page, deleting the others.
    func mergeAllOntoOnePage() {
        let allImages = pages.flatMap { $0.images }.prefix(Self.maxImagesPerPage).map { img -> CollageImage in
            var i = img
            i.panOffset = .zero
            i.zoom = 1.0
            i.lastBoxSize = .zero
            return i
        }
        var page = CollagePage(style: currentPage.style)
        page.images = Array(allImages)
        page.order = allImages.map(\.id)
        page.style.numCols = max(1, min(allImages.count, 6))
        page.layout.rebuild(images: page.images, order: page.order, numCols: page.style.numCols)
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
        let styleTemplate = currentPage.style
        let perPage = min(Self.maxImagesPerPage,
                          Int((Double(images.count) / Double(pageCount)).rounded(.up)))

        var newPages: [CollagePage] = []
        var idx = 0
        for _ in 0..<pageCount {
            var page = CollagePage(style: styleTemplate)
            var chunk: [CollageImage] = []
            while chunk.count < perPage && idx < images.count {
                var img = images[idx]
                img.panOffset = .zero
                img.zoom = 1.0
                img.lastBoxSize = .zero
                chunk.append(img)
                idx += 1
            }
            page.images = chunk
            page.order = chunk.map(\.id)
            // Columns ≈ √count so rows and columns stay balanced — a square-ish
            // grid (4 → 2×2, 6 → 3×2, 9 → 3×3, 12 → 4×3). Callers may override
            // with a different strategy (e.g. Burst!'s landscape bias).
            page.style.numCols = columnsFor?(chunk.count)
                ?? max(1, min(6, Int(Double(chunk.count).squareRoot().rounded())))
            page.layout.rebuild(images: page.images, order: page.order,
                                numCols: page.style.numCols)
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
        guard !allImages.isEmpty else { return }
        let styleTemplate = currentPage.style

        var newPages: [CollagePage] = []
        for var img in allImages.prefix(Self.maxPages) {
            img.panOffset = .zero
            img.zoom = 1.0
            img.lastBoxSize = .zero
            var page = CollagePage(style: styleTemplate)
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
                img.zoom = 1.0
                img.lastBoxSize = .zero
                last.images.append(img)
                last.order.append(img.id)
            }
            last.style.numCols = min(last.images.count, 6)
            last.layout.rebuild(images: last.images, order: last.order,
                                numCols: last.style.numCols)
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
    func resetStyle() {
        gap = 10
        canvasMargin = 0
        backgroundColor = .white
        cornerRadius = 20
        borderStyle = .solid
        borderThickness = 0
        borderColor = .white
    }

    func clear() {
        pages = [CollagePage()]
        currentPageIndex = 0
        imageFrames.removeAll()
        clearSwapDrag()
    }

    // MARK: - Layout

    func rebuildLayout(resetGrows: Bool = false) {
        if resetGrows { layout.resetGrows() }
        layout.rebuild(images: images, order: order, numCols: numCols)
        objectWillChange.send()
    }

    func setRatio(_ r: CanvasRatio) {
        ratio = r
        if r != .custom {
            canvasSize = r.canvasSize(base: 1024)
        }
        resetAllImagePositions()
        rebuildAllPages()
        saveRatio()
    }

    func applyCustomSize() {
        let wRaw = CGFloat(Double(customWidth) ?? 1200)
        let hRaw = CGFloat(Double(customHeight) ?? 900)
        let w = customUnit.toPx(wRaw)
        let h = customUnit.toPx(hRaw)
        canvasSize = CGSize(width: max(100, min(6000, w)), height: max(100, min(6000, h)))
        ratio = .custom
        resetAllImagePositions()
        rebuildAllPages()
        saveRatio()
    }

    // MARK: - Persistence (ratio + shuffle options)

    private enum DefaultsKey {
        static let ratio = "ratioRaw"
        static let customWidth = "customWidth"
        static let customHeight = "customHeight"
        static let customUnit = "customUnit"
        static let shuffle = "shuffleOptions"
    }

    init() {
        restoreSettings()
    }

    private func restoreSettings() {
        let d = UserDefaults.standard

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
        if let raw = d.string(forKey: DefaultsKey.ratio), let r = CanvasRatio(rawValue: raw) {
            ratio = r
            if r == .custom {
                let wpx = customUnit.toPx(CGFloat(Double(customWidth) ?? 1200))
                let hpx = customUnit.toPx(CGFloat(Double(customHeight) ?? 900))
                canvasSize = CGSize(width: max(100, min(6000, wpx)),
                                    height: max(100, min(6000, hpx)))
            } else {
                canvasSize = r.canvasSize(base: 1024)
            }
        }
    }

    private func saveRatio() {
        let d = UserDefaults.standard
        d.set(ratio.rawValue, forKey: DefaultsKey.ratio)
        d.set(customWidth, forKey: DefaultsKey.customWidth)
        d.set(customHeight, forKey: DefaultsKey.customHeight)
        d.set(customUnit.rawValue, forKey: DefaultsKey.customUnit)
    }

    private func saveShuffleOptions() {
        let o = shuffleOptions
        UserDefaults.standard.set(
            [o.columns, o.spacing, o.rounding, o.borderStyle,
             o.borderThickness, o.borderPosition, o.color],
            forKey: DefaultsKey.shuffle)
    }

    func resetAllImagePositions() {
        for pi in pages.indices {
            for i in pages[pi].images.indices {
                pages[pi].images[i].panOffset = .zero
                pages[pi].images[i].zoom = 1.0
                pages[pi].images[i].rotation = 0
                pages[pi].images[i].lastBoxSize = .zero
            }
        }
    }

    /// Rebuilds the layout of every page — used when a global setting that
    /// affects arrangement (columns, ratio) changes.
    func rebuildAllPages(resetGrows: Bool = true) {
        for pi in pages.indices {
            if resetGrows { pages[pi].layout.resetGrows() }
            pages[pi].layout.rebuild(images: pages[pi].images,
                                     order: pages[pi].order,
                                     numCols: pages[pi].style.numCols)
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
        images[idx] = img
    }

    func setPan(id: UUID, pan normalizedPan: CGSize, boxSize: CGSize) {
        guard let idx = images.firstIndex(where: { $0.id == id }) else { return }
        var img = images[idx]
        let px = Self.panPixels(normalizedPan, in: boxSize)
        let clamped = clamp(pan: px, zoom: img.zoom, boxSize: boxSize, naturalSize: img.naturalSize)
        img.panOffset = Self.normalizedPan(clamped, in: boxSize)
        img.lastBoxSize = boxSize
        images[idx] = img
    }

    func setBoxSize(id: UUID, boxSize: CGSize) {
        guard let idx = images.firstIndex(where: { $0.id == id }) else { return }
        images[idx].lastBoxSize = boxSize
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
        img.zoom = max(1.0, min(4.0, img.zoom * scaleFactor))
        img.rotation += angleDelta
        let panPx = Self.panPixels(img.panOffset, in: boxSize)
        let clamped = clamp(pan: panPx, zoom: img.zoom, boxSize: boxSize, naturalSize: img.naturalSize)
        img.panOffset = Self.normalizedPan(clamped, in: boxSize)
        img.lastBoxSize = boxSize
        images[idx] = img
    }

    func resetTransform(id: UUID) {
        guard let idx = images.firstIndex(where: { $0.id == id }) else { return }
        images[idx].panOffset = .zero
        images[idx].zoom = 1.0
        images[idx].rotation = 0
    }

    func clamp2(pan: CGSize, zoom: CGFloat, boxSize: CGSize, naturalSize: CGSize) -> CGSize {
        print("[EDGE CHECK] pan.width=\(pan.width), image.width=\(naturalSize.width), box.width=\(boxSize.width)")
        return pan
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
    }

    func updateResizeBoxes(colIndex: Int, biA: Int, biB: Int, totalDeltaFraction: CGFloat) {
        guard colIndex < dragStartBoxGrows.count else { return }
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
        guard ciA < dragStartColGrows.count, ciB < dragStartColGrows.count else { return }
        
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
        guard colIndex < layout.boxGrows.count else { return }
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
        guard ciA < layout.colGrows.count, ciB < layout.colGrows.count else { return }
        
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
        resetTransform(id: id1)
        resetTransform(id: id2)
        clearSwapDrag()
        rebuildLayout(resetGrows: false)
    }

    func updateImageFrame(id: UUID, frame: CGRect) {
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
        dropTargetId = swapTargetId(at: location, excluding: sourceId)
        dropTargetEmptyCol = dropTargetId == nil ? emptySlotTarget(at: location) : nil
    }

    func finishSwapDrag(sourceId: UUID, location: CGPoint) {
        if let targetId = swapTargetId(at: location, excluding: sourceId) {
            swapImages(id1: sourceId, id2: targetId)
        } else if let col = emptySlotTarget(at: location) {
            moveImageToEmptyColumn(id: sourceId, columnIndex: col)
        } else {
            clearSwapDrag()
        }
        // Safety net: whatever path ran, never leave a drag stuck.
        if draggingId != nil { clearSwapDrag() }
    }

    func clearSwapDrag() {
        swapArmedId = nil
        draggingId = nil
        dropTargetId = nil
        dropTargetEmptyCol = nil
        dragOffset = .zero
    }

    /// Belt-and-braces reset of every transient interaction flag. If any
    /// gesture were ever cancelled without its `onEnded` firing, these could
    /// stick and lock out input — calling this guarantees a clean slate so
    /// the page can never stay frozen.
    func clearInteractionLocks() {
        clearSwapDrag()
        imageZoomingId = nil
        isCanvasZooming = false
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
        resetTransform(id: id)
        clearSwapDrag()
    }

    func imageFrame(for id: UUID) -> CGRect? {
        imageFrames[id]
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
        return true
    }

    func endImageZoom(id: UUID) {
        if imageZoomingId == id {
            imageZoomingId = nil
        }
    }

    // MARK: - Export

    /// Exports the current page, or all non-empty pages, as pixel-perfect
    /// PNG files named 001.png … 00N.png, then presents the share sheet.
    func exportPages(allPages: Bool) async {
        guard hasAnyImages else { return }
        isExporting = true
        isBusy = true
        isLoading = true
        showExportSheet = false
        savePhase = .saving
        // Let the "Exporting" dialog animate in before the render blocks the main thread
        try? await Task.sleep(nanoseconds: 350_000_000)

        // Draw the full-resolution originals for the export snapshots
        renderFullResolution = true
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
        for (n, pi) in targets.enumerated() {
            currentPageIndex = pi
            guard let image = renderCurrentPage(),
                  let data = Self.pngData(image) else { continue }
            let url = dir.appendingPathComponent(String(format: "%03d.png", n + 1))
            do {
                try data.write(to: url)
                urls.append(url)
            } catch {
                print("Export failed for page \(pi + 1): \(error)")
            }
            exportProgress = Double(n + 1) / Double(targets.count)
            // Let the progress bar repaint between pages.
            await Task.yield()
        }

        currentPageIndex = originalIndex
        renderFullResolution = false
        isExporting = false
        isBusy = false
        isLoading = false
        savePhase = .idle
        exportedFiles = urls
        if !urls.isEmpty {
            showExportSheet = true
        }
    }

    /// Snapshots the currently selected page at full canvas resolution using
    /// SwiftUI's `ImageRenderer`. This renders the view tree in isolation
    /// (no window / hosting controller needed), which is both the supported
    /// way to rasterize a SwiftUI view and free of the offscreen
    /// `drawHierarchy(afterScreenUpdates:)` crash.
    @MainActor
    private func renderCurrentPage() -> PlatformImage? {
        let gridView = CollageGridView_Grid(scale: 1.0)
            .frame(width: canvasSize.width, height: canvasSize.height)
            .environmentObject(self)

        let renderer = ImageRenderer(content: gridView)
        renderer.proposedSize = ProposedViewSize(canvasSize)
        // 2× the 1024-pt canvas → crisp export while staying memory-safe.
        renderer.scale = 2.0
        renderer.isOpaque = false

        #if canImport(UIKit)
        return renderer.uiImage
        #else
        return renderer.nsImage
        #endif
    }

    private static func pngData(_ image: PlatformImage) -> Data? {
        #if canImport(UIKit)
        return image.pngData()
        #else
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
        #endif
    }
}
