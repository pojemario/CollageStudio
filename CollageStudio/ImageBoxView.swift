import SwiftUI

struct ImageBoxView: View {
    /// Toggle to overlay live transform numbers on each image for debugging.
    static let showDebug = false

    @EnvironmentObject var state: CollageState
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var hSizeClass
    #endif
    let imageId: UUID
    /// Display scale of the canvas. Used to scale border thickness and corner
    /// radius so the on-screen preview matches the full-resolution export exactly.
    var scale: CGFloat = 1.0

    /// True while the user is previewing full screen on iPhone (bottom panel
    /// hidden). Editing helpers like the placeholder outline hide with it.
    /// iPad/macOS use the sidebar, so they never count as previewing.
    private var isPreviewing: Bool {
        #if os(macOS)
        return false
        #else
        return hSizeClass == .compact && !state.isPanelOpen
        #endif
    }

    @State private var livePanOffset: CGSize = .zero
    // Live pinch/rotate deltas. @GestureState is GUARANTEED to reset to its
    // initial value when the gesture ends or is cancelled, so the manipulation
    // can never leave the input layer stuck.
    @GestureState private var pinching = false
    @GestureState private var gestureScale: CGFloat = 1.0
    @GestureState private var gestureRotation: Angle = .zero

    var imgData: CollageImage? { state.images.first(where: { $0.id == imageId }) }

    var body: some View {
        GeometryReader { geo in
            let boxSize = geo.size

            imageLayer(boxSize: boxSize)
                .frame(width: boxSize.width, height: boxSize.height)
                // Clip the image first, then draw the border on top — a
                // center/outer border extends beyond the box bounds and must
                // not be cut off by the clip shape.
                .clipShape(RoundedRectangle(cornerRadius: state.cornerRadius * scale))
                .overlay(
                    Group {
                        // Empty placeholders never take the global border —
                        // they stay an intentional blank space.
                        if state.borderThickness > 0, imgData?.isPlaceholder != true {
                            let lineWidth = CGFloat(state.borderThickness) * scale
                            if state.borderStyle.usesStamps {
                                StampedBorderView(cornerRadius: state.cornerRadius * scale,
                                                  inset: state.borderPlacement.inset(lineWidth: lineWidth),
                                                  lineWidth: lineWidth,
                                                  color: state.borderColor,
                                                  style: state.borderStyle)
                            } else {
                                ConcentricRoundedBorder(cornerRadius: state.cornerRadius * scale,
                                                        inset: state.borderPlacement.inset(lineWidth: lineWidth))
                                    .stroke(state.borderColor, style: state.borderStyle.strokeStyle(lineWidth: lineWidth))
                            }
                        }
                    }
                    .allowsHitTesting(false)
                )
                .overlay(
                    Group {
                        // Only while a swap drag is actually in progress — a
                        // stale dropTargetId must never leave an overlay covering
                        // (and blocking touches on) an image.
                        if state.draggingId != nil {
                            if state.dropTargetId == imageId {
                                // Hovered swap target — tint the whole image so
                                // the drop zone reads clearly, not just an edge.
                                RoundedRectangle(cornerRadius: state.cornerRadius * scale)
                                    .fill(Color.accentColor.opacity(0.35))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: state.cornerRadius * scale)
                                            .stroke(Color.accentColor, lineWidth: 3)
                                    )
                            } else if state.draggingId != imageId {
                                // Mark this box as a possible target.
                                RoundedRectangle(cornerRadius: state.cornerRadius * scale)
                                    .stroke(Color.accentColor.opacity(0.45),
                                            style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                            }
                        }
                    }
                    // Decoration only — never intercept gestures on the image.
                    .allowsHitTesting(false)
                )
                // Faint dashed outline marking an "empty image" placeholder so
                // it stays findable while editing. Not drawn during export or
                // full-screen preview (bottom panel hidden).
                .overlay(
                    Group {
                        if let img = imgData, img.isPlaceholder,
                           !state.renderFullResolution, !isPreviewing {
                            RoundedRectangle(cornerRadius: state.cornerRadius * scale)
                                .strokeBorder(Color.gray.opacity(0.35),
                                              style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        }
                    }
                    .allowsHitTesting(false)
                )
                // The text box being edited in the panel.
                .overlay(
                    Group {
                        if state.textEditTargetId == imageId, !state.renderFullResolution {
                            RoundedRectangle(cornerRadius: state.cornerRadius * scale)
                                .strokeBorder(Color.accentColor, lineWidth: 2)
                        }
                    }
                    .allowsHitTesting(false)
                )
                .overlay(alignment: .topLeading) {
                    if Self.showDebug && !state.renderFullResolution {
                        Text(debugText(boxSize: boxSize))
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(3)
                            .background(Color.black.opacity(0.55))
                            .cornerRadius(4)
                            .padding(2)
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
                // Track this box's frame in canvas space for swap hit-testing.
                // A dedicated background GeometryReader with `initial: true`
                // reports the *settled* frame in the proper layout context —
                // unlike onAppear, which can fire before the named coordinate
                // space resolves and seed a wrong frame (breaking swap until an
                // unrelated relayout finally corrects it).
                .background(
                    GeometryReader { bg in
                        let frame = bg.frame(in: .named("collageCanvas"))
                        Color.clear
                            .onChange(of: frame, initial: true) { _, newFrame in
                                updateTrackedGeometry(frame: newFrame, boxSize: newFrame.size)
                                guard let img = imgData else { return }
                                if img.lastBoxSize != newFrame.size {
                                    state.setPan(id: imageId, pan: img.panOffset, boxSize: newFrame.size)
                                }
                            }
                    }
                )
                .offset(state.draggingId == imageId ? state.dragOffset : .zero)
                .scaleEffect(state.draggingId == imageId ? 1.03 : 1.0)
                .shadow(color: state.draggingId == imageId ? .black.opacity(0.3) : .clear, radius: 14, x: 0, y: 8)
                .zIndex(state.draggingId == imageId ? 10 : 0)
                .highPriorityGesture(panGesture(boxSize: boxSize))
                // Empty-image placeholders are blank, so zoom/rotate is
                // meaningless — don't attach the pinch recognizers at all
                // (.subviews keeps the wrapped gestures like pan working).
                .simultaneousGesture(pinchGesture(boxSize: boxSize),
                                     including: (imgData?.isPlaceholder ?? false) ? .subviews : .all)
                // NOTE: no standalone minimumDistance-0 DragGesture may ever be
                // attached here — one stranded in its "began" state blocks
                // every other recognizer on the view, leaving the box deaf to
                // all touches. The action-menu location comes from a drag
                // SEQUENCED after the long press instead (see below), and the
                // popover itself lives on the canvas container.
                .simultaneousGesture(replaceLongPressGesture)
                // Double-tap resets this image; on a text box a single tap
                // opens it for live editing instead (exclusive, so a double
                // tap never also opens the editor). Simultaneous (not high
                // priority) so it never delays the pan drag from starting.
                // Zoom and rotate need two fingers, pan needs a drag, so a
                // plain tap can't be mistaken for any of them.
                .simultaneousGesture(
                    TapGesture(count: 2)
                        .onEnded {
                            // Reset this image, and clear any transient
                            // interaction flags so a double-tap always
                            // unfreezes the page if a gesture ever left one
                            // stuck.
                            state.clearInteractionLocks()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                state.resetTransform(id: imageId)
                            }
                            #if canImport(UIKit)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                        }
                        .exclusively(before: TapGesture().onEnded {
                            if imgData?.isText == true { state.beginEditText(id: imageId) }
                        })
                )
                // Drive the global "an image is being pinched" flag from the
                // @GestureState — which always resets — so it can never stick
                // and lock out further input.
                .onChange(of: pinching) { _, active in
                    if active {
                        state.collapsePanel()
                        state.closeRatio()
                        _ = state.beginImageZoom(id: imageId)
                    } else {
                        state.endImageZoom(id: imageId)
                        // Rebuild the view (fresh gesture recognizers) after
                        // EVERY pinch — completed or cancelled — but only on
                        // the next runloop tick, after the gesture system has
                        // fully torn down (a synchronous rebuild mid-teardown
                        // can itself strand recognizers).
                        Task { @MainActor in
                            state.bumpGestureEpoch(id: imageId)
                        }
                    }
                }
                .id(imgData?.gestureEpoch ?? 0)
        }
    }

    func updateTrackedGeometry(frame: CGRect, boxSize: CGSize) {
        state.updateImageFrame(id: imageId, frame: frame)
        state.setBoxSize(id: imageId, boxSize: boxSize)
    }

    // MARK: - Image layer

    @ViewBuilder
    func imageLayer(boxSize: CGSize) -> some View {
        if let img = imgData,
           boxSize.width > 1, boxSize.height > 1,
           img.naturalSize.width > 1, img.naturalSize.height > 1 {
            let natural = img.naturalSize
            // Committed transform combined with the live gesture deltas.
            let rawZoom = img.zoom * gestureScale
            let effectiveZoom = rawZoom.isFinite ? max(1.0, min(4.0, rawZoom)) : 1.0
            let rawRot = img.rotation + CGFloat(gestureRotation.radians)
            let effectiveRotation = rawRot.isFinite ? rawRot : 0
            // Exact aspect-fill cover for the *rotated* box: the box rotated
            // into image space has extents (bw, bh); the image (keeping its
            // aspect ratio) must be at least that big to leave no gaps at any
            // angle.
            let c = abs(cos(effectiveRotation)), s = abs(sin(effectiveRotation))
            let bw = boxSize.width * c + boxSize.height * s
            let bh = boxSize.width * s + boxSize.height * c
            let aspect = max(0.05, min(20, natural.width / natural.height))
            let rw = max(bw, bh * aspect) * effectiveZoom
            let rh = rw / aspect
            // Stored pan is normalized to box size; convert to pixels for
            // this render scale (preview or export). Clamp against the rotated
            // cover so panning can't reveal a gap at any angle.
            let basePan = CollageState.panPixels(img.panOffset, in: boxSize)
            let maxPanX = max(0, (rw - bw) / 2)
            let maxPanY = max(0, (rh - bh) / 2)
            let livePan = CGSize(
                width: min(max(basePan.width + livePanOffset.width, -maxPanX), maxPanX),
                height: min(max(basePan.height + livePanOffset.height, -maxPanY), maxPanY)
            )

            // Canvas uses the downscaled proxy; export swaps in the original.
            // Both share the same aspect ratio and target frame, so geometry
            // is identical either way.
            let displayImage = state.renderFullResolution ? img.image : img.proxy
            // Guard against any non-finite geometry that would collapse the
            // image to a white box.
            let safeW = (rw.isFinite && rw > 0) ? rw : boxSize.width
            let safeH = (rh.isFinite && rh > 0) ? rh : boxSize.height
            // Rendered via an Equatable subview so unrelated state changes
            // (other pages, busy flags, etc.) don't re-rasterize the image —
            // it only redraws when its own geometry/rotation actually change.
            CollageImageContent(image: displayImage,
                                width: safeW, height: safeH,
                                rotation: effectiveRotation,
                                offset: livePan)
                .equatable()
        } else if let img = imgData {
            // Degenerate box/image size — fall back to a plain fill so the
            // frame never goes blank.
            let displayImage = state.renderFullResolution ? img.image : img.proxy
            #if canImport(UIKit)
            Image(uiImage: displayImage).resizable().scaledToFill().allowsHitTesting(false)
            #else
            Image(nsImage: displayImage).resizable().scaledToFill().allowsHitTesting(false)
            #endif
        }
    }

    // MARK: - Debug readout

    func debugText(boxSize: CGSize) -> String {
        guard let img = imgData else { return "NO IMG" }
        let z = img.zoom * gestureScale
        let deg = (img.rotation + CGFloat(gestureRotation.radians)) * 180 / .pi
        // Which render path is active: the transform branch or the static
        // scaledToFill fallback (which ignores zoom/rotation entirely).
        let fallback = !(boxSize.width > 1 && boxSize.height > 1
                         && img.naturalSize.width > 1 && img.naturalSize.height > 1)
        return String(format: "z %.2f  r %.0f°%@%@\np %.2f,%.2f\nbox %.0f×%.0f  nat %.0f×%.0f",
                      z, deg,
                      img.isPlaceholder ? "  PH" : "",
                      fallback ? "  FALLBACK" : "",
                      img.panOffset.width, img.panOffset.height,
                      boxSize.width, boxSize.height,
                      img.naturalSize.width, img.naturalSize.height)
    }

    // MARK: - Pan gesture


    func panGesture(boxSize: CGSize) -> some Gesture {
        // Slightly higher minimumDistance to avoid accidental swap trigger
        DragGesture(minimumDistance: 4, coordinateSpace: .named("collageCanvas"))
            .onChanged { value in
                // Ignore the stray single-finger drag a two-finger pinch/rotate
                // produces from its moving centroid.
                guard !pinching,
                      !state.isCanvasZooming,
                      state.imageZoomingId == nil else {
                    livePanOffset = .zero
                    return
                }

                // If we're currently swapping this image, keep swap updates live
                if state.draggingId == imageId {
                    livePanOffset = .zero
                    state.updateSwapDrag(location: value.location,
                                         translation: value.translation,
                                         excluding: imageId)
                    return
                }

                // If any other swap is active, ignore panning here
                guard state.draggingId == nil else { return }

                // Panning owns the drag everywhere — swap only engages once
                // the finger is actually over ANOTHER image's box (the one it
                // would be swapped with) or over an empty placeholder box.
                // Gaps and edges still pan.
                if state.swapTargetId(at: value.location, excluding: imageId) != nil
                    || state.emptySlotTarget(at: value.location) != nil {
                    livePanOffset = .zero
                    state.beginSwapDrag(id: imageId)
                    state.updateSwapDrag(location: value.location,
                                         translation: value.translation,
                                         excluding: imageId)
                    return
                }

                // Starting to work on the canvas hides the panels in the same
                // motion (no separate tap-to-close first).
                state.collapsePanel()
                state.closeRatio()
                // Otherwise, live-pan inside the box
                livePanOffset = value.translation
            }
            .onEnded { value in
                // A two-finger pinch/rotate can spawn a stray single-finger
                // drag from the moving centroid — don't commit it as a pan.
                if pinching || state.imageZoomingId != nil {
                    livePanOffset = .zero
                    return
                }
                if state.draggingId == imageId {
                    state.finishSwapDrag(sourceId: imageId, location: value.location)
                } else {
                    state.updatePan(id: imageId, delta: value.translation, boxSize: boxSize)
                }
                livePanOffset = .zero
            }
    }

    // MARK: - Box actions via long press

    /// Holding still on a box for 1 second opens the Replace / Delete menu
    /// for this image (a single popover on the canvas container). The menu
    /// opens the moment the timer fires — the sequence transitions to .second
    /// right then, while the finger is still down. The sequenced drag (which
    /// only starts recognizing after the long press, so it can never sit
    /// armed on every touch like a standalone min-0 drag) refines the anchor
    /// to the exact finger point once it delivers an event; until then the
    /// box's own frame anchors the popover.
    var replaceLongPressGesture: some Gesture {
        LongPressGesture(minimumDuration: 1.0, maximumDistance: 8)
            .sequenced(before: DragGesture(minimumDistance: 0,
                                           coordinateSpace: .named("collageCanvas")))
            .onChanged { value in
                if case .second(true, let drag) = value {
                    showActionMenu(at: drag?.startLocation)
                }
            }
            .onEnded { value in
                if case .second(true, let drag) = value {
                    showActionMenu(at: drag?.startLocation)
                }
            }
    }

    /// Opens the action menu popover anchored at a canvas-space point, or at
    /// the box's tracked frame when the exact finger point isn't known yet.
    private func showActionMenu(at point: CGPoint?) {
        guard !state.showBoxActionMenu,
              state.draggingId == nil,
              state.imageZoomingId == nil,
              !state.isCanvasZooming else { return }
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        let boxCenter = state.imageFrame(for: imageId)
            .map { CGPoint(x: $0.midX, y: $0.midY) } ?? .zero
        state.boxActionPressPoint = point ?? boxCenter
        state.boxActionTargetId = imageId
        state.showBoxActionMenu = true
    }

    // MARK: - Pinch + rotate gesture

    /// Two-finger pinch to zoom and rotate simultaneously, like Photos.
    /// The live scale/angle live purely in @GestureState (updated below) and
    /// are rendered locally, so the model isn't mutated mid-gesture — that's
    /// what keeps the gesture from being cancelled (white flash / stuck input).
    /// The final transform is committed once on end.
    func pinchGesture(boxSize: CGSize) -> some Gesture {
        SimultaneousGesture(MagnificationGesture(), RotationGesture())
            // Feed the wedge watchdog on every update — a pinch that goes
            // silent without ending gets its box force-rebuilt (see
            // CollageState.noteZoomActivity).
            .onChanged { _ in
                state.noteZoomActivity(id: imageId)
            }
            .updating($pinching) { _, isPinching, _ in
                isPinching = true
            }
            .updating($gestureScale) { value, scale, _ in
                if let m = value.first { scale = m }
            }
            .updating($gestureRotation) { value, rotation, _ in
                if let a = value.second { rotation = a }
            }
            .onEnded { value in
                let finalScale = value.first ?? 1.0
                let finalAngle = value.second ?? .zero
                state.commitZoomRotate(id: imageId,
                                       scaleFactor: finalScale,
                                       angleDelta: CGFloat(finalAngle.radians),
                                       boxSize: boxSize)
            }
    }

}

// MARK: - Box action menu (long-press popover)

/// Replace / Move / Delete menu shown in a popover anchored at the pressed
/// point on an image box. Mirrors the options of the old bottom dialog.
struct BoxActionMenu: View {
    @EnvironmentObject var state: CollageState
    let imageId: UUID

    var body: some View {
        let source = state.pageIndex(containing: imageId)
        let movablePages = state.pages.indices.filter { pi in
            pi != source && state.pages[pi].images.count < CollageState.maxImagesPerPage
        }

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                menuButton("Replace", sf: "photo.on.rectangle.angled") {
                    state.showReplacePicker = true
                    state.showBoxActionMenu = false
                }
                ForEach(movablePages, id: \.self) { pi in
                    Divider()
                    menuButton("Move to Page \(pi + 1)", sf: "arrow.right.square") {
                        state.moveImage(id: imageId, toPage: pi)
                        dismissMenu()
                    }
                }
                if state.pages.count < CollageState.maxPages {
                    Divider()
                    menuButton("Move to New Page", sf: "plus.square.on.square") {
                        state.moveImageToNewPage(id: imageId)
                        dismissMenu()
                    }
                }
                Divider()
                menuButton("Delete", sf: "trash", destructive: true) {
                    state.removeImage(id: imageId)
                    dismissMenu()
                }
            }
        }
        .frame(width: 220)
        // Hug the content, but never grow taller than a comfortable popover.
        .frame(maxHeight: min(CGFloat(3 + movablePages.count) * 44 + 8, 320))
    }

    private func dismissMenu() {
        state.boxActionTargetId = nil
        state.showBoxActionMenu = false
    }

    private func menuButton(_ title: String, sf: String, destructive: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: sf)
            }
            .font(.subheadline)
            .foregroundColor(destructive ? .red : .primary)
            .padding(.horizontal, 14)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Image content (Equatable for performance)

/// The transformed image inside a box. Being `Equatable` lets SwiftUI skip
/// re-rendering (and re-decoding) it whenever a state change doesn't actually
/// alter this image's geometry — critical for smooth manipulation.
struct CollageImageContent: View, Equatable {
    let image: PlatformImage
    let width: CGFloat
    let height: CGFloat
    let rotation: CGFloat
    let offset: CGSize

    static func == (l: CollageImageContent, r: CollageImageContent) -> Bool {
        l.image === r.image
            && l.width == r.width
            && l.height == r.height
            && l.rotation == r.rotation
            && l.offset == r.offset
    }

    var body: some View {
        #if canImport(UIKit)
        Image(uiImage: image)
            .resizable()
            .frame(width: width, height: height)
            .rotationEffect(.radians(Double(rotation)))
            .offset(x: offset.width, y: offset.height)
            .allowsHitTesting(false)
        #else
        Image(nsImage: image)
            .resizable()
            .frame(width: width, height: height)
            .rotationEffect(.radians(Double(rotation)))
            .offset(x: offset.width, y: offset.height)
            .allowsHitTesting(false)
        #endif
    }
}

// MARK: - Empty placeholder box

/// Placeholder shown in columns that have no image yet — a transparent
/// "image box" that draws just the page's border treatment, so extra
/// columns look like empty frame slots. On the canvas it also acts as a
/// drop target for swap drags.
struct EmptyBoxView: View {
    @EnvironmentObject var state: CollageState
    var scale: CGFloat = 1.0
    /// Column index on the canvas — enables drop targeting. Nil when the
    /// view is used purely decoratively.
    var columnIndex: Int? = nil

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .overlay(
                    Group {
                        if state.borderThickness > 0 {
                            let lineWidth = CGFloat(state.borderThickness) * scale
                            if state.borderStyle.usesStamps {
                                StampedBorderView(cornerRadius: state.cornerRadius * scale,
                                                  inset: state.borderPlacement.inset(lineWidth: lineWidth),
                                                  lineWidth: lineWidth,
                                                  color: state.borderColor,
                                                  style: state.borderStyle)
                            } else {
                                ConcentricRoundedBorder(cornerRadius: state.cornerRadius * scale,
                                                        inset: state.borderPlacement.inset(lineWidth: lineWidth))
                                    .stroke(state.borderColor,
                                            style: state.borderStyle.strokeStyle(lineWidth: lineWidth))
                            }
                        }
                    }
                )
                // While a swap drag is active, reveal the slot as a possible
                // drop target; solid + thicker when hovered.
                .overlay(
                    Group {
                        if state.draggingId != nil, let columnIndex {
                            let hovered = state.dropTargetEmptyCol == columnIndex
                            RoundedRectangle(cornerRadius: state.cornerRadius * scale)
                                .stroke(Color.accentColor.opacity(hovered ? 1.0 : 0.45),
                                        style: StrokeStyle(lineWidth: hovered ? 3 : 2, dash: [6, 4]))
                        }
                    }
                )
                .onAppear {
                    if let columnIndex {
                        state.emptySlotFrames[columnIndex] = geo.frame(in: .named("collageCanvas"))
                    }
                }
                .onChange(of: geo.frame(in: .named("collageCanvas"))) { _, frame in
                    if let columnIndex {
                        state.emptySlotFrames[columnIndex] = frame
                    }
                }
                .onDisappear {
                    if let columnIndex {
                        state.emptySlotFrames.removeValue(forKey: columnIndex)
                    }
                }
        }
    }
}

// MARK: - Concentric rounded border

/// Rounded-rect border path whose corner radius shrinks/grows with the inset,
/// so the border stays concentric with the box's clip shape. Keeping the full
/// radius on an inset rect would make the border curve away from the image
/// corners, leaving visible gaps at high rounding values.
struct ConcentricRoundedBorder: Shape {
    var cornerRadius: CGFloat
    var inset: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        guard r.width > 0, r.height > 0 else { return Path() }
        let radius = max(0, min(cornerRadius - inset, min(r.width, r.height) / 2))
        return Path(roundedRect: r, cornerRadius: radius)
    }
}

// MARK: - Stamped border (triangles / slashes / crosses)

/// Draws a border made of small repeated shapes stamped along the border
/// rectangle, following its rounded corners and rotating with the path
/// direction. Stamp size tracks the border thickness; color and placement
/// come from the same settings as the stroked styles.
struct StampedBorderView: View {
    let cornerRadius: CGFloat
    let inset: CGFloat
    let lineWidth: CGFloat
    let color: Color
    let style: BorderStyle

    // Canvas clips to its bounds, so grow it beyond the box to keep
    // center/outer stamps visible.
    private var pad: CGFloat { max(lineWidth * 2, 8) }

    var body: some View {
        Canvas { context, size in
            let boxRect = CGRect(x: pad, y: pad,
                                 width: size.width - pad * 2,
                                 height: size.height - pad * 2)
            let rect = boxRect.insetBy(dx: inset, dy: inset)
            guard rect.width > 4, rect.height > 4, lineWidth > 0 else { return }

            // Concentric radius: shrink (inner) or grow (outer) with the inset
            // so the stamp path hugs the image's rounded corners without gaps.
            let radius = max(0, min(cornerRadius - inset, min(rect.width, rect.height) / 2))
            let path = Path(roundedRect: rect, cornerRadius: radius)

            // Rounded-rect perimeter: straight edges + corner arcs
            let perimeter = 2 * (rect.width + rect.height) - 8 * radius + 2 * .pi * radius
            // Per-style rhythm: triangles touch each other, crosses nearly
            // touch, slashes keep a small gap.
            let spacing: CGFloat
            switch style {
            case .triangles: spacing = max(lineWidth, 3)
            case .crosses:   spacing = max(lineWidth * 1.15, 3)
            default:         spacing = max(lineWidth * 1.5, 4)
            }
            let count = min(512, max(4, Int(perimeter / spacing)))

            let stamp = Self.stampPath(for: style, size: lineWidth)
            let strokeWidth = max(1, lineWidth * 0.25)

            for i in 0..<count {
                let t = CGFloat(i) / CGFloat(count)
                // Sample the path position and a point slightly ahead to get
                // the local direction, so stamps rotate around corners.
                let here = path.trimmedPath(from: t, to: min(t + 0.002, 1)).boundingRect
                let ahead = path.trimmedPath(from: min(t + 0.004, 1), to: min(t + 0.006, 1)).boundingRect
                let pos = CGPoint(x: here.midX, y: here.midY)
                let nxt = CGPoint(x: ahead.midX, y: ahead.midY)
                let angle = atan2(nxt.y - pos.y, nxt.x - pos.x)

                let transform = CGAffineTransform(translationX: pos.x, y: pos.y)
                    .rotated(by: angle)
                let placed = stamp.applying(transform)

                if style == .triangles {
                    context.fill(placed, with: .color(color))
                } else {
                    context.stroke(placed, with: .color(color),
                                   style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                }
            }
        }
        .padding(-pad)
        .allowsHitTesting(false)
    }

    /// A single stamp shape centered on the origin, sized to the thickness.
    /// Internal so pattern previews can reuse the exact same shapes.
    static func stampPath(for style: BorderStyle, size s: CGFloat) -> Path {
        var p = Path()
        let h = s / 2
        switch style {
        case .triangles:
            // Apex on +y so the triangles point inward, toward the image
            p.move(to: CGPoint(x: 0, y: h))
            p.addLine(to: CGPoint(x: h, y: -h))
            p.addLine(to: CGPoint(x: -h, y: -h))
            p.closeSubpath()
        case .slashes:
            p.move(to: CGPoint(x: -h, y: h))
            p.addLine(to: CGPoint(x: h, y: -h))
        case .crosses:
            p.move(to: CGPoint(x: -h, y: h))
            p.addLine(to: CGPoint(x: h, y: -h))
            p.move(to: CGPoint(x: -h, y: -h))
            p.addLine(to: CGPoint(x: h, y: h))
        default:
            break
        }
        return p
    }
}
