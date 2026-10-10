import SwiftUI
import Combine

/// Everything that makes up the collage document: what undo steps back to
/// and what a project saves. Session and UI state (panel, selection,
/// gestures, the page being looked at) stays out of the comparison.
struct CollageSnapshot {
    var pages: [CollagePage]
    var currentPageIndex: Int
    var ratio: CanvasRatio
    var canvasSize: CGSize
    var customWidth: String
    var customHeight: String
    var customUnit: CustomUnit
    var canvasMargin: Double
    var canvasRotation: Double
    var canvasFrame: CanvasFrameSet?
    var overlayLayers: [OverlayLayer]
    var effects: [CollageEffect: Double]
    var hsl: HSLAdjustments
    var calibration: CameraCalibration
    var colorFilter: ColorFilter
    var filterStrength: Double

    /// Same document, ignoring bookkeeping that changes on its own: box
    /// sizes, gesture epochs, text bitmaps re-rendered for a new box shape,
    /// and which page is on screen.
    func sameDocument(as o: CollageSnapshot) -> Bool {
        ratio == o.ratio && canvasSize == o.canvasSize
            && customWidth == o.customWidth && customHeight == o.customHeight && customUnit == o.customUnit
            && canvasMargin == o.canvasMargin && canvasRotation == o.canvasRotation
            && canvasFrame == o.canvasFrame && overlayLayers == o.overlayLayers
            && effects == o.effects && hsl == o.hsl && calibration == o.calibration
            && colorFilter == o.colorFilter && filterStrength == o.filterStrength
            && pages.count == o.pages.count
            && zip(pages, o.pages).allSatisfy { $0.sameContent(as: $1) }
    }

    /// The first page whose content differs from `o`'s, if any.
    func firstDifferingPage(from o: CollageSnapshot) -> Int? {
        for i in pages.indices {
            guard o.pages.indices.contains(i), pages[i].sameContent(as: o.pages[i]) else { return i }
        }
        return nil
    }
}

extension CollagePage {
    func sameContent(as o: CollagePage) -> Bool {
        id == o.id && order == o.order && style == o.style
            && images.count == o.images.count
            && zip(images, o.images).allSatisfy { $0.sameContent(as: $1) }
            && layout.sameContent(as: o.layout)
    }
}

extension CollageLayout {
    func sameContent(as o: CollageLayout) -> Bool {
        colGrows == o.colGrows && boxGrows == o.boxGrows
            && columns.map { $0.map(\.imageId) } == o.columns.map { $0.map(\.imageId) }
    }
}

extension CollageImage {
    func sameContent(as o: CollageImage) -> Bool {
        // A text box is defined by its style; its bitmap is re-rendered
        // whenever its box changes shape.
        let samePicture = isText || o.isText ? textStyle == o.textStyle : image === o.image
        return id == o.id && samePicture && isPlaceholder == o.isPlaceholder
            && protrusion == o.protrusion && protrusionEffect == o.protrusionEffect
            && protrusionObjects == o.protrusionObjects
            && panOffset == o.panOffset && zoom == o.zoom && rotation == o.rotation
    }
}

// MARK: - Undo / redo

extension CollageState {
    var documentSnapshot: CollageSnapshot {
        CollageSnapshot(pages: pages, currentPageIndex: currentPageIndex,
                        ratio: ratio, canvasSize: canvasSize,
                        customWidth: customWidth, customHeight: customHeight, customUnit: customUnit,
                        canvasMargin: canvasMargin, canvasRotation: canvasRotation,
                        canvasFrame: canvasFrame, overlayLayers: overlayLayers,
                        effects: effects, hsl: hsl, calibration: calibration,
                        colorFilter: colorFilter, filterStrength: filterStrength)
    }

    /// Puts a document in place as is (no re-layout, no reset positions).
    func applyDocument(_ s: CollageSnapshot, pageIndex: Int? = nil) {
        pages = s.pages.isEmpty ? [CollagePage()] : s.pages
        currentPageIndex = min(max(pageIndex ?? s.currentPageIndex, 0), pages.count - 1)
        ratio = s.ratio
        canvasSize = s.canvasSize
        customWidth = s.customWidth
        customHeight = s.customHeight
        customUnit = s.customUnit
        canvasMargin = s.canvasMargin
        canvasRotation = s.canvasRotation
        canvasFrame = s.canvasFrame
        overlayLayers = s.overlayLayers
        if let sel = selectedOverlayId, !overlayLayers.contains(where: { $0.id == sel }) {
            selectedOverlayId = overlayLayers.last?.id
        }
        effects = s.effects
        hsl = s.hsl
        calibration = s.calibration
        colorFilter = s.colorFilter
        filterStrength = s.filterStrength
    }

    /// Watches for edits: once changes settle (and no finger is still on a
    /// slider, splitter, drag or pinch), the document before them becomes
    /// one undo step. Recording after the fact means every edit is covered
    /// without each one having to register itself.
    func observeHistory() {
        historyCommitted = documentSnapshot
        historyWatcher = objectWillChange
            .debounce(for: .milliseconds(450), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.commitHistoryIfChanged() }
            }
    }

    /// Records the pending change, if any, as an undo step.
    func commitHistoryIfChanged() {
        // Mid-gesture: the gesture's end publishes again and comes back here.
        guard activeAdjustment == nil, !isResizing, draggingId == nil, imageZoomingId == nil,
              !isExporting, !isLoading else { return }
        let now = documentSnapshot
        guard let previous = historyCommitted else {
            historyCommitted = now
            return
        }
        historyCommitted = now
        guard !now.sameDocument(as: previous) else { return }
        undoStack.append(previous)
        if undoStack.count > Self.maxUndoSteps { undoStack.removeFirst() }
        redoStack.removeAll()
        updateHistoryFlags()
        documentDidChange()
    }

    func undo() {
        commitHistoryIfChanged()
        guard let target = undoStack.popLast(), let current = historyCommitted else { return }
        redoStack.append(current)
        restoreHistory(target, from: current)
    }

    func redo() {
        commitHistoryIfChanged()
        guard let target = redoStack.popLast(), let current = historyCommitted else { return }
        undoStack.append(current)
        restoreHistory(target, from: current)
    }

    /// Starts a fresh history (a different collage was opened).
    func resetHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
        historyCommitted = documentSnapshot
        updateHistoryFlags()
    }

    private func restoreHistory(_ target: CollageSnapshot, from current: CollageSnapshot) {
        endTextEditing()
        endProtrusionEditing()
        clearSwapDrag()
        overlayPreview = nil
        // Show the page the step changed, if it isn't the one on screen.
        let changed = target.firstDifferingPage(from: current)
        let page = changed.map { min($0, max(target.pages.count - 1, 0)) } ?? currentPageIndex
        withAnimation(.easeInOut(duration: 0.25)) {
            applyDocument(target, pageIndex: page)
        }
        historyCommitted = documentSnapshot
        imageFrames.removeAll()
        emptySlotFrames.removeAll()
        refreshTrackedGeometry(after: 0.45)
        updateHistoryFlags()
        documentDidChange()
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    private func updateHistoryFlags() {
        if canUndo != !undoStack.isEmpty { canUndo = !undoStack.isEmpty }
        if canRedo != !redoStack.isEmpty { canRedo = !redoStack.isEmpty }
    }

    /// Brief message over the canvas ("Undo", "Redo"), e.g. after a shake.
    func flashHistoryToast(_ text: String) {
        historyToast = text
        historyToastToken &+= 1
        let token = historyToastToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
            guard let self, self.historyToastToken == token else { return }
            withAnimation(.easeOut(duration: 0.2)) { self.historyToast = nil }
        }
    }
}

#if canImport(UIKit)
extension Notification.Name {
    static let deviceDidShake = Notification.Name("CollageStudio.deviceDidShake")
}

extension UIWindow {
    /// Shake to undo: the window hears the shake and passes it on.
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
}
#endif

/// Undo / redo buttons for the top bar (and the sidebar header).
struct UndoRedoButtons: View {
    @EnvironmentObject var state: CollageState
    var size: CGFloat = 40

    var body: some View {
        HStack(spacing: 0) {
            button("arrow.uturn.backward", label: "Undo", enabled: state.canUndo) { state.undo() }
            button("arrow.uturn.forward", label: "Redo", enabled: state.canRedo) { state.redo() }
        }
    }

    private func button(_ sf: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: sf)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(enabled ? .primary : .secondary.opacity(0.35))
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

/// The "Undo" / "Redo" message after a shake.
struct HistoryToast: View {
    @EnvironmentObject var state: CollageState

    var body: some View {
        ZStack {
            if let text = state.historyToast {
                Label(text, systemImage: text == "Undo" ? "arrow.uturn.backward" : "arrow.uturn.forward")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.black.opacity(0.6)))
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(.easeOut(duration: 0.18), value: state.historyToast)
        .allowsHitTesting(false)
    }
}
