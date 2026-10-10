import SwiftUI
import Vision

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
    /// Set once a touch on this box has moved (pan or swap drag), so the tap
    /// that SwiftUI still reports when the finger lifts isn't taken as a tap.
    @State private var touchMoved = false
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
                            .onChange(of: TrackedFrame(frame: frame, epoch: state.geometryEpoch),
                                      initial: true) { _, tracked in
                                let newFrame = tracked.frame
                                // Offscreen copies (export, effect snapshot)
                                // must not overwrite on-screen geometry.
                                guard !state.isRenderingOffscreen else { return }
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
                        .exclusively(before: SpatialTapGesture().onEnded { tap in
                            // Protrude panel open on this photo: a tap picks
                            // or drops the subject under the finger.
                            if state.protrusionTargetId == imageId {
                                toggleSubject(at: tap.location, boxSize: boxSize)
                                return
                            }
                            guard imgData?.isText == true else { return }
                            // SwiftUI reports a tap even after a drag, as long
                            // as the finger lifts inside the box. Wait a beat
                            // for the drag's end to land, and only open the
                            // editor if the finger never moved.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                if !touchMoved { state.beginEditText(id: imageId) }
                            }
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
                // A protruding photo shares its in-flight pan / pinch with the
                // protrusion layer, which then follows the finger live.
                .onChange(of: LiveValues(pan: livePanOffset, scale: gestureScale,
                                         rotation: CGFloat(gestureRotation.radians))) { _, v in
                    guard imgData?.protrusion != nil else { return }
                    state.liveGesture.update(id: imageId, pan: v.pan, scale: v.scale, rotation: v.rotation)
                }
                // Re-grade the picture whenever the grade or the picture changes.
                .task(id: GradeKey(proxy: imgData.map { ObjectIdentifier($0.proxy) }, grade: state.contentGrade)) {
                    if let img = imgData { state.gradeIfNeeded(img) }
                }
                .id(imgData?.gestureEpoch ?? 0)
        }
    }

    private struct LiveValues: Equatable {
        let pan: CGSize
        let scale: CGFloat
        let rotation: CGFloat
    }

    private struct GradeKey: Equatable {
        let proxy: ObjectIdentifier?
        let grade: ContentGrade
    }

    func updateTrackedGeometry(frame: CGRect, boxSize: CGSize) {
        state.updateImageFrame(id: imageId, frame: frame)
        state.setBoxSize(id: imageId, boxSize: boxSize)
    }

    // MARK: - Image layer

    @ViewBuilder
    func imageLayer(boxSize: CGSize) -> some View {
        // Committed transform combined with the live gesture deltas. Stored
        // pan is normalized to box size; converted to points for this render
        // scale (preview or export).
        if let img = imgData,
           let placement = ImagePlacement.compute(
               natural: img.naturalSize, boxSize: boxSize,
               zoom: img.zoom * gestureScale,
               rotation: img.rotation + CGFloat(gestureRotation.radians),
               pan: {
                   let base = CollageState.panPixels(img.panOffset, in: boxSize)
                   return CGSize(width: base.width + livePanOffset.width,
                                 height: base.height + livePanOffset.height)
               }()) {
            // Canvas uses the downscaled proxy; export swaps in the original.
            // Both share the same aspect ratio and target frame, so geometry
            // is identical either way.
            let displayImage = state.gradedDisplayImage(for: img)
            // Rendered via an Equatable subview so unrelated state changes
            // (other pages, busy flags, etc.) don't re-rasterize the image —
            // it only redraws when its own geometry/rotation actually change.
            CollageImageContent(image: displayImage,
                                width: placement.size.width, height: placement.size.height,
                                rotation: placement.rotation,
                                offset: placement.offset)
                .equatable()
        } else if let img = imgData {
            // Degenerate box/image size — fall back to a plain fill so the
            // frame never goes blank.
            let displayImage = state.gradedDisplayImage(for: img)
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

    /// Includes or leaves out the subject under a tap (box coordinates).
    private func toggleSubject(at point: CGPoint, boxSize: CGSize) {
        guard let img = imgData, let subject = state.subjectMask(for: img), subject.instances.count > 1,
              let placement = ImagePlacement.compute(natural: img.naturalSize, boxSize: boxSize, zoom: img.zoom,
                                                     rotation: img.rotation,
                                                     pan: CollageState.panPixels(img.panOffset, in: boxSize))
        else { return }
        // Box point → normalized image point (undo pan, rotation, size).
        let x = point.x - boxSize.width / 2 - placement.offset.width
        let y = point.y - boxSize.height / 2 - placement.offset.height
        let c = cos(placement.rotation), s = sin(placement.rotation)
        let u = (x * c + y * s) / placement.size.width + 0.5
        let v = (-x * s + y * c) / placement.size.height + 0.5
        if let index = subject.instance(atU: u, v: v) {
            if img.protrusion == nil {
                // Picking a subject also turns protrusion on, across all edges.
                state.setProtrusion(.all, for: img.id)
            }
            state.toggleProtrusionObject(index, for: img.id)
        }
    }

    // MARK: - Pan gesture


    func panGesture(boxSize: CGSize) -> some Gesture {
        // Slightly higher minimumDistance to avoid accidental swap trigger
        DragGesture(minimumDistance: 4, coordinateSpace: .named("collageCanvas"))
            .onChanged { value in
                touchMoved = true
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
                // would be swapped with), an empty placeholder box, or a
                // splitter to insert at. Elsewhere it pans.
                if state.swapTargetId(at: value.location, excluding: imageId) != nil
                    || state.emptySlotTarget(at: value.location) != nil
                    || state.insertTarget(at: value.location, excluding: imageId) != nil {
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
                // Otherwise, live-pan inside the box.
                livePanOffset = value.translation
            }
            .onEnded { value in
                // Outlive the tap check above, then arm for the next touch.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { touchMoved = false }
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

    /// Holding still on a box for half a second (the iOS standard) opens the
    /// Replace / Delete menu
    /// for this image (a single popover on the canvas container). The menu
    /// opens the moment the timer fires — the sequence transitions to .second
    /// right then, while the finger is still down. The sequenced drag (which
    /// only starts recognizing after the long press, so it can never sit
    /// armed on every touch like a standalone min-0 drag) refines the anchor
    /// to the exact finger point once it delivers an event; until then the
    /// box's own frame anchors the popover.
    var replaceLongPressGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.5, maximumDistance: 8)
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

/// A box's canvas frame plus the re-report epoch (see
/// CollageState.geometryEpoch): a change in either makes the box report.
struct TrackedFrame: Equatable {
    let frame: CGRect
    let epoch: Int
}

// MARK: - Box action menu (long-press popover)

/// Hosts the long-press action menu at the root of the app, above the canvas
/// AND the bottom panel. The card is placed at the pressed point. It is drawn
/// in SwiftUI rather than as a popover, so it gets the app's corner radius —
/// and per-box popovers must not be used anyway: after swaps they left
/// orphaned UIKit presentation views over the box that swallowed all its
/// touches.
struct BoxActionMenuLayer: View {
    @EnvironmentObject var state: CollageState

    var body: some View {
        ZStack {
            if state.showBoxActionMenu, let id = state.boxActionTargetId {
                GeometryReader { geo in
                    let frame = geo.frame(in: .global)
                    let size = CGSize(width: BoxActionMenu.width,
                                      height: BoxActionMenu.height(state: state, imageId: id))
                    let press = CGPoint(
                        x: state.boxActionCanvasOrigin.x + state.boxActionPressPoint.x - frame.minX,
                        y: state.boxActionCanvasOrigin.y + state.boxActionPressPoint.y - frame.minY)
                    // Below the finger if it fits, otherwise above it;
                    // always fully on screen.
                    let below = press.y + 12 + size.height <= geo.size.height - 8
                    let y = below ? press.y + 12 + size.height / 2 : press.y - 12 - size.height / 2
                    let x = min(max(press.x, size.width / 2 + 8), geo.size.width - size.width / 2 - 8)
                    ZStack {
                        // Tap anywhere else to dismiss.
                        Color.black.opacity(0.001)
                            .contentShape(Rectangle())
                            .onTapGesture { dismiss() }
                        BoxActionMenu(imageId: id)
                            .position(x: x, y: min(max(y, size.height / 2 + 8),
                                                   geo.size.height - size.height / 2 - 8))
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .animation(.easeOut(duration: 0.15), value: state.showBoxActionMenu)
    }

    /// Tapping outside clears the target too, unless the Replace picker
    /// took over.
    private func dismiss() {
        state.showBoxActionMenu = false
        if !state.showReplacePicker { state.boxActionTargetId = nil }
    }
}

/// Replace / Move / Delete menu: a floating card placed at the pressed point
/// on an image box (see CanvasContainerView).
struct BoxActionMenu: View {
    @EnvironmentObject var state: CollageState
    let imageId: UUID

    static let width: CGFloat = 230
    private static let rowHeight: CGFloat = 44

    private static func canProtrude(_ state: CollageState, _ imageId: UUID) -> Bool {
        state.images.first { $0.id == imageId }?.canProtrude ?? false
    }

    private static func movablePages(_ state: CollageState, _ imageId: UUID) -> [Int] {
        let source = state.pageIndex(containing: imageId)
        return state.pages.indices.filter { pi in
            pi != source && state.pages[pi].images.count < CollageState.maxImagesPerPage
        }
    }

    /// Hugs the rows, but never taller than a comfortable menu. Static, so
    /// the container can place the card before it's on screen.
    static func height(state: CollageState, imageId: UUID) -> CGFloat {
        let rows = 2 + movablePages(state, imageId).count
            + (state.pages.count < CollageState.maxPages ? 1 : 0)
            + (canProtrude(state, imageId) ? 1 : 0)
        return min(CGFloat(rows) * rowHeight + 8, 320)
    }

    var body: some View {
        let movablePages = Self.movablePages(state, imageId)
        let height = Self.height(state: state, imageId: imageId)
        let shape = RoundedRectangle(cornerRadius: ButtonStyleGuide.cornerRadius, style: .continuous)

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if Self.canProtrude(state, imageId) {
                    menuButton("PROTRUDE", sf: "person.crop.square") {
                        state.beginProtrusion(id: imageId)
                        dismissMenu()
                    }
                    Divider()
                }
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
                menuButton("Remove", sf: "trash", destructive: true) {
                    state.removeImage(id: imageId)
                    dismissMenu()
                }
            }
            .padding(.vertical, 4)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: Self.width, height: height)
        .background(.regularMaterial, in: shape)
        .overlay(shape.strokeBorder(ColorManager.glassStroke, lineWidth: 0.8))
        .clipShape(shape)
        .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
    }

    private func dismissMenu() {
        state.boxActionTargetId = nil
        state.showBoxActionMenu = false
    }

    private func menuButton(_ title: String, sf: String, destructive: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: sf)
                    .frame(width: 22)
                Text(title)
                Spacer(minLength: 0)
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
    @State private var reportedFrame: CGRect?

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
                // Same reporting as the image boxes: `initial: true` gives the
                // settled frame (onAppear can fire before the named space
                // resolves), and offscreen copies never report.
                .onChange(of: TrackedFrame(frame: geo.frame(in: .named("collageCanvas")),
                                           epoch: state.geometryEpoch),
                          initial: true) { _, tracked in
                    let frame = tracked.frame
                    guard let columnIndex, !state.isRenderingOffscreen else { return }
                    state.emptySlotFrames[columnIndex] = frame
                    reportedFrame = frame
                }
                .onDisappear {
                    // Only drop the entry if it's still ours — a slot of the
                    // incoming page (same column index) may already have
                    // replaced it during a page transition.
                    if let columnIndex, let reportedFrame,
                       state.emptySlotFrames[columnIndex] == reportedFrame {
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

// MARK: - Subject masks (protrusion)

/// A photo's subject cut out by Vision (the same tech as Photos' "lift
/// subject" / stickers): an alpha mask matching the upright picture, plus
/// the subject's bounds in normalized image coordinates (0...1, y down).
struct SubjectMask {
    /// The original image it was made from (a replaced photo needs a new one).
    let source: ObjectIdentifier
    /// White, with all subjects as alpha. Nil when no subject was found.
    let mask: CGImage?
    let bounds: CGRect
    /// Each subject separately (a person, a dog, a held bike…), in Vision's
    /// order — what a photo's protrusion can pick from.
    var instances: [SubjectInstance] = []
    /// Which subject each pixel belongs to (index + 1, 0 = none), at a
    /// quarter of the mask's resolution — for tapping a subject.
    var labels: [UInt8] = []
    var labelWidth = 0
    var labelHeight = 0

    /// The subject under a point in normalized image coordinates, if any.
    func instance(atU u: CGFloat, v: CGFloat) -> Int? {
        guard labelWidth > 0, labelHeight > 0, u >= 0, u < 1, v >= 0, v < 1 else { return nil }
        let x = Int(u * CGFloat(labelWidth)), y = Int(v * CGFloat(labelHeight))
        let label = Int(labels[y * labelWidth + x])
        return label > 0 ? label - 1 : nil
    }
}

struct SubjectInstance {
    let mask: CGImage
    let bounds: CGRect
}

enum SubjectMasker {
    /// Long edge the mask is computed at — sharp enough for export, quick to
    /// compute, and the same mask serves the canvas and the export.
    static let maskLongEdge: CGFloat = 1600

    static func makeMask(for image: PlatformImage) -> SubjectMask {
        let none = SubjectMask(source: ObjectIdentifier(image), mask: nil, bounds: .zero)
        guard let cg = uprightCGImage(image, longEdge: maskLongEdge) else { return none }
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        let request = VNGenerateForegroundInstanceMaskRequest()
        do { try handler.perform([request]) } catch { return none }
        guard let observation = request.results?.first, !observation.allInstances.isEmpty,
              let buffer = try? observation.generateScaledMaskForImage(forInstances: observation.allInstances,
                                                                       from: handler)
        else { return none }
        guard let (mask, bounds) = alphaMask(from: buffer) else { return none }
        var result = SubjectMask(source: ObjectIdentifier(image), mask: mask, bounds: bounds)

        // Each subject on its own, plus a label map for tapping them.
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        let lw = max(w / 4, 1), lh = max(h / 4, 1)
        var labels = [UInt8](repeating: 0, count: lw * lh)
        var strongest = [Float](repeating: 0.5, count: lw * lh)
        for index in observation.allInstances.sorted() {
            guard let single = try? observation.generateScaledMaskForImage(forInstances: IndexSet(integer: index),
                                                                           from: handler),
                  let (instanceMask, instanceBounds) = alphaMask(from: single) else { continue }
            let label = UInt8(min(result.instances.count + 1, 255))
            result.instances.append(SubjectInstance(mask: instanceMask, bounds: instanceBounds))
            stampLabels(from: single, label: label, into: &labels, strongest: &strongest, width: lw, height: lh)
        }
        result.labels = labels
        result.labelWidth = lw
        result.labelHeight = lh
        return result
    }

    /// Marks the label-map cells where this subject is the strongest.
    private static func stampLabels(from buffer: CVPixelBuffer, label: UInt8, into labels: inout [UInt8],
                                    strongest: inout [Float], width lw: Int, height lh: Int) {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        for ly in 0..<lh {
            let y = min(ly * h / lh, h - 1)
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float32.self)
            for lx in 0..<lw {
                let v = row[min(lx * w / lw, w - 1)]
                let i = ly * lw + lx
                if v > strongest[i] { strongest[i] = v; labels[i] = label }
            }
        }
    }

    /// Several subject masks merged into one.
    static func union(_ masks: [CGImage]) -> CGImage? {
        guard var merged = masks.first.map({ CIImage(cgImage: $0) }) else { return nil }
        let extent = merged.extent
        for m in masks.dropFirst() {
            merged = CIImage(cgImage: m).applyingFilter("CIMaximumCompositing",
                                                       parameters: [kCIInputBackgroundImageKey: merged])
        }
        return ciContext.createCGImage(merged.cropped(to: extent), from: extent)
    }

    private static let ciContext = CIContext()

    /// Outer outlines of a mask as polylines in normalized image coordinates
    /// (0...1, y down), traced with Vision; specks are dropped.
    static func outline(of mask: CGImage) -> [[CGPoint]] {
        let request = VNDetectContoursRequest()
        request.detectsDarkOnLight = false          // white subject on clear
        request.maximumImageDimension = 768
        do { try VNImageRequestHandler(cgImage: mask, options: [:]).perform([request]) } catch { return [] }
        guard let observation = request.results?.first else { return [] }
        return observation.topLevelContours.compactMap { contour in
            let points = contour.normalizedPoints.map { CGPoint(x: CGFloat($0.x), y: 1 - CGFloat($0.y)) }
            guard points.count > 8 else { return nil }
            let xs = points.map(\.x), ys = points.map(\.y)
            let area = (xs.max()! - xs.min()!) * (ys.max()! - ys.min()!)
            return area > 0.0005 ? points : nil
        }
    }

    /// The mask grown outward by `radius` pixels (a solid silhouette for the
    /// Border effect).
    static func dilate(_ mask: CGImage, radius: Int) -> CGImage? {
        guard radius > 0 else { return mask }
        let input = CIImage(cgImage: mask)
        let extent = input.extent
        let grown = input.clampedToExtent()
            .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: extent)
        return ciContext.createCGImage(grown, from: extent)
    }

    /// The picture drawn upright (orientation applied) at most `longEdge`
    /// long, so the mask lines up with how the photo is displayed.
    private static func uprightCGImage(_ image: PlatformImage, longEdge: CGFloat) -> CGImage? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let k = min(1, longEdge / max(size.width, size.height))
        let target = CGSize(width: max(1, (size.width * k).rounded()), height: max(1, (size.height * k).rounded()))
        #if canImport(UIKit)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }.cgImage
        #else
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(target.width), pixelsHigh: Int(target.height),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        guard let rep else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: CGRect(origin: .zero, size: target))
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage
        #endif
    }

    /// Vision's float mask → a white RGBA image with the mask as alpha, and
    /// the subject's normalized bounds.
    private static func alphaMask(from buffer: CVPixelBuffer) -> (CGImage, CGRect)? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent32Float,
              let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float32.self)
            for x in 0..<w {
                let v = min(max(row[x], 0), 1)
                let a = UInt8((v * 255).rounded())
                let i = (y * w + x) * 4
                // Premultiplied white: every channel equals alpha.
                pixels[i] = a; pixels[i + 1] = a; pixels[i + 2] = a; pixels[i + 3] = a
                if v > 0.5 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= minX, maxY >= minY,
              let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        let bounds = CGRect(x: CGFloat(minX) / CGFloat(w), y: CGFloat(minY) / CGFloat(h),
                            width: CGFloat(maxX - minX + 1) / CGFloat(w), height: CGFloat(maxY - minY + 1) / CGFloat(h))
        return (image, bounds)
    }
}

// MARK: - Protrusion layer

/// The live (uncommitted) pan / pinch of the photo being touched, shared
/// with its protrusion. Updated by the photo's box during the gesture.
final class LiveGesture: ObservableObject {
    struct Values: Equatable {
        var id: UUID?
        var pan: CGSize = .zero
        var scale: CGFloat = 1
        var rotation: CGFloat = 0
        static let identity = Values()
    }

    @Published private(set) var current = Values()

    func update(id: UUID, pan: CGSize, scale: CGFloat, rotation: CGFloat) {
        let idle = pan == .zero && scale == 1 && rotation == 0
        let next = idle ? Values() : Values(id: id, pan: pan, scale: scale, rotation: rotation)
        if next != current { current = next }
    }
}

/// Draws each protruding photo's subject again above all boxes: the same
/// graded picture with the same placement as in its box, but unclipped,
/// masked to the subject, and limited to the box plus the space beyond its
/// chosen edges. Inside the box it covers its own picture exactly, so only
/// the parts the box crops away show — over the border and the neighbours.
struct ProtrusionLayer: View {
    @EnvironmentObject var state: CollageState
    let canvasSize: CGSize
    let gap: CGFloat
    /// Display scale of the canvas (border thickness and shadow follow it).
    var scale: CGFloat = 1
    /// In-flight pan / pinch of a protruding photo (follows it live).
    @ObservedObject var live: LiveGesture

    var body: some View {
        let rects = state.layout.rects(canvasSize: canvasSize, gap: gap, rows: state.isRows)
        ZStack(alignment: .topLeading) {
            ForEach(state.images.filter { $0.protrusion != nil && $0.canProtrude }) { img in
                protrusion(img, box: rects[img.id])
                    // Masks are made on demand (also after a photo is replaced).
                    .task(id: ObjectIdentifier(img.image)) { state.requestSubjectMask(for: img) }
            }
            // While its Protrude panel is open, a photo shows what Vision
            // found — never in exports.
            if let id = state.protrusionTargetId, !state.isRenderingOffscreen,
               let img = state.images.first(where: { $0.id == id }) {
                preview(img, box: rects[id])
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    /// Hidden while its box is being dragged to another spot or resized;
    /// panning and pinching the photo inside its box are followed live.
    private func isHidden(_ id: UUID) -> Bool {
        state.draggingId == id || state.isResizing
    }

    @ViewBuilder
    private func protrusion(_ img: CollageImage, box: CGRect?) -> some View {
        let g = live.current.id == img.id ? live.current : .identity
        if let box, let edges = img.protrusion, !edges.isEmpty, !isHidden(img.id),
           let mask = state.protrusionShape(for: img)?.mask,
           let placement = ImagePlacement.compute(
               natural: img.naturalSize, boxSize: box.size,
               zoom: img.zoom * g.scale, rotation: img.rotation + g.rotation,
               pan: {
                   let base = CollageState.panPixels(img.panOffset, in: box.size)
                   return CGSize(width: base.width + g.pan.width, height: base.height + g.pan.height)
               }()) {
            let allowed = allowedRegion(box: box, edges: edges)
            ZStack {
                // Effects sit under the subject and only show outside its
                // box, so the photo inside the box stays untouched.
                effect(img, mask: mask, placement: placement, box: box, isLive: g.id != nil)
                    .mask { outsideBox(allowed: allowed, box: box) }
                placed(placement: placement, box: box) {
                    Group {
                        #if canImport(UIKit)
                        Image(uiImage: state.gradedDisplayImage(for: img)).resizable()
                        #else
                        Image(nsImage: state.gradedDisplayImage(for: img)).resizable()
                        #endif
                    }
                    .mask(Image(decorative: mask, scale: 1).resizable())
                }
                .mask(alignment: .topLeading) {
                    Rectangle()
                        .frame(width: allowed.width, height: allowed.height)
                        .offset(x: allowed.minX, y: allowed.minY)
                }
            }
        }
    }

    /// The subject preview: each subject Vision found, tinted and outlined
    /// when it protrudes, dash-outlined when left out, with a number badge
    /// (the panel's object chips; tap a subject in the photo to switch it).
    /// The parts beyond the box show as a ghost, fainter past edges that are
    /// off.
    @ViewBuilder
    private func preview(_ img: CollageImage, box: CGRect?) -> some View {
        let g = live.current.id == img.id ? live.current : .identity
        if let box, let subject = state.subjectMask(for: img), !subject.instances.isEmpty, !isHidden(img.id),
           let placement = ImagePlacement.compute(
               natural: img.naturalSize, boxSize: box.size,
               zoom: img.zoom * g.scale, rotation: img.rotation + g.rotation,
               pan: {
                   let base = CollageState.panPixels(img.panOffset, in: box.size)
                   return CGSize(width: base.width + g.pan.width, height: base.height + g.pan.height)
               }()) {
            let outlines = state.subjectInstanceOutlines(for: img)
            let several = subject.instances.count > 1
            let allowed = allowedRegion(box: box, edges: img.protrusion ?? [])
            placed(placement: placement, box: box) {
                GeometryReader { geo in
                    ZStack {
                        ForEach(Array(subject.instances.enumerated()), id: \.offset) { i, instance in
                            let included = img.protrusion != nil && (img.protrusionObjects?.contains(i) ?? true)
                            if included {
                                Color.accentColor.opacity(0.3)
                                    .mask(Image(decorative: instance.mask, scale: 1).resizable())
                            }
                            if i < outlines.count {
                                SubjectOutlineShape(outline: outlines[i])
                                    .stroke(included ? Color.accentColor : Color.white,
                                            style: StrokeStyle(lineWidth: 2, lineJoin: .round,
                                                               dash: included ? [] : [6, 4]))
                                    .shadow(color: .black.opacity(0.35), radius: 1)
                            }
                            if several {
                                Text("\(i + 1)")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 22, height: 22)
                                    .background(Circle().fill(included ? Color.accentColor : Color.black.opacity(0.55)))
                                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 1.5))
                                    .position(x: instance.bounds.midX * geo.size.width,
                                              y: instance.bounds.minY * geo.size.height + 14)
                            }
                        }
                    }
                }
            }
            // Full strength inside the box, a ghost outside it: fainter past
            // the edges that are off.
            .mask(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    Color.white.opacity(0.2)
                    Rectangle().fill(Color.white.opacity(0.5))
                        .frame(width: allowed.width, height: allowed.height)
                        .offset(x: allowed.minX, y: allowed.minY)
                    Rectangle().fill(Color.white)
                        .frame(width: box.width, height: box.height)
                        .offset(x: box.minX, y: box.minY)
                }
                .frame(width: canvasSize.width, height: canvasSize.height)
            }
        }
    }

    /// Content laid out the way the photo sits in its box (size, rotation,
    /// pan), positioned at the box, on a canvas-sized frame.
    private func placed<Content: View>(placement: ImagePlacement, box: CGRect,
                                       @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(width: placement.size.width, height: placement.size.height)
            .rotationEffect(.radians(Double(placement.rotation)))
            .offset(x: placement.offset.width, y: placement.offset.height)
            .frame(width: box.width, height: box.height)
            .position(x: box.midX, y: box.midY)
            .frame(width: canvasSize.width, height: canvasSize.height)
    }

    @ViewBuilder
    private func effect(_ img: CollageImage, mask: CGImage, placement: ImagePlacement, box: CGRect,
                        isLive: Bool) -> some View {
        switch img.protrusionEffect {
        case .none:
            EmptyView()
        case .border:
            // Follows the Layout border: its color, thickness and pattern.
            let lineWidth = CGFloat(state.borderThickness) * scale
            let pixelsPerPoint = CGFloat(mask.width) / max(placement.size.width, 1)
            let style = state.borderStyle
            if style == .solid {
                // Solid: the silhouette grown by the thickness, filled.
                let radius = min(Int((lineWidth * pixelsPerPoint).rounded()), 80)
                if radius > 0, let grown = state.dilatedSubjectMask(for: img, radius: radius, allowStale: isLive) {
                    placed(placement: placement, box: box) {
                        state.borderColor.mask(Image(decorative: grown, scale: 1).resizable())
                    }
                }
            } else if lineWidth > 0 {
                // Patterned: drawn along the outline traced half a line
                // width outside the subject, so the line sits just outside.
                let radius = max(1, min(Int((lineWidth / 2 * pixelsPerPoint).rounded()), 60))
                let outline = state.subjectOutline(for: img, radius: radius, allowStale: isLive)
                placed(placement: placement, box: box) {
                    SubjectOutlineBorder(outline: outline, style: style,
                                         lineWidth: lineWidth, color: state.borderColor)
                }
            }
        case .shadow:
            placed(placement: placement, box: box) {
                Color.black.opacity(0.65).mask(Image(decorative: mask, scale: 1).resizable())
            }
            .blur(radius: 9 * scale)
            .offset(y: 6 * scale)
        }
    }

    /// The allowed region minus the box itself.
    private func outsideBox(allowed: CGRect, box: CGRect) -> some View {
        Path { p in
            p.addRect(allowed)
            p.addRect(box)
        }
        .fill(style: FillStyle(eoFill: true))
        .frame(width: canvasSize.width, height: canvasSize.height)
    }

    /// The box, opened up to the canvas edge on every allowed side.
    private func allowedRegion(box: CGRect, edges: ProtrusionEdges) -> CGRect {
        let minX = edges.contains(.left) ? 0 : box.minX
        let maxX = edges.contains(.right) ? canvasSize.width : box.maxX
        let minY = edges.contains(.top) ? 0 : box.minY
        let maxY = edges.contains(.bottom) ? canvasSize.height : box.maxY
        return CGRect(x: minX, y: minY, width: max(maxX - minX, 0), height: max(maxY - minY, 0))
    }
}

/// A subject outline (normalized polylines) as a shape filling its frame.
struct SubjectOutlineShape: Shape {
    let outline: [[CGPoint]]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for line in outline where line.count > 1 {
            path.addLines(line.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) })
            path.closeSubpath()
        }
        return path
    }
}

/// The Layout border's pattern drawn along a subject outline (normalized
/// polylines, scaled to the view): dash styles as a stroke, stamp styles
/// (triangles, slashes, crosses) placed along it like on the box border.
struct SubjectOutlineBorder: View {
    let outline: [[CGPoint]]
    let style: BorderStyle
    let lineWidth: CGFloat
    let color: Color

    var body: some View {
        Canvas { context, size in
            let polylines = outline.map { $0.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) } }
            if style.usesStamps {
                drawStamps(polylines, in: &context)
            } else {
                var path = Path()
                for line in polylines where line.count > 1 {
                    path.addLines(line)
                    path.closeSubpath()
                }
                context.stroke(path, with: .color(color), style: style.strokeStyle(lineWidth: lineWidth))
            }
        }
        .allowsHitTesting(false)
    }

    private func drawStamps(_ polylines: [[CGPoint]], in context: inout GraphicsContext) {
        // Same rhythm and shapes as StampedBorderView.
        let spacing: CGFloat
        switch style {
        case .triangles: spacing = max(lineWidth, 3)
        case .crosses:   spacing = max(lineWidth * 1.15, 3)
        default:         spacing = max(lineWidth * 1.5, 4)
        }
        let stamp = StampedBorderView.stampPath(for: style, size: lineWidth)
        let strokeWidth = max(1, lineWidth * 0.25)
        var budget = 1500
        for line in polylines where line.count > 1 {
            let closed = line + [line[0]]
            var carried: CGFloat = 0           // distance since the last stamp
            for i in 0..<(closed.count - 1) {
                let a = closed[i], b = closed[i + 1]
                let segment = hypot(b.x - a.x, b.y - a.y)
                guard segment > 0 else { continue }
                let angle = atan2(b.y - a.y, b.x - a.x)
                var d = spacing - carried
                while d <= segment, budget > 0 {
                    let t = d / segment
                    let pos = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                    let placed = stamp.applying(CGAffineTransform(translationX: pos.x, y: pos.y).rotated(by: angle))
                    if style == .triangles {
                        context.fill(placed, with: .color(color))
                    } else {
                        context.stroke(placed, with: .color(color),
                                       style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                    }
                    budget -= 1
                    d += spacing
                }
                carried = segment - (d - spacing)
            }
        }
    }
}

// MARK: - Protrusion panel

/// Panel (long-press menu → Protrude) for one photo: turn its subject's
/// protrusion on or off and pick the edges it may break out across.
struct ProtrusionPanel: View {
    @EnvironmentObject var state: CollageState
    let imageId: UUID

    private var img: CollageImage? { state.images.first { $0.id == imageId } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Protrude", systemImage: "person.crop.square")
                    .font(.headline)
                Spacer()
                if let img {
                    Toggle("Protrude", isOn: Binding(
                        get: { img.protrusion != nil },
                        set: { on in state.setProtrusion(on ? .all : nil, for: img.id) }))
                        .labelsHidden()
                        .tint(.accentColor)
                        .disabled(state.subjectMask(for: img)?.mask == nil)
                }
            }
            if let img { content(img) }
        }
        .panelChrome(state)
        // The photo was deleted or moved to another page: nothing to edit.
        .onChange(of: img == nil, initial: true) { _, gone in
            if gone { state.endProtrusionEditing() }
        }
    }

    @ViewBuilder
    private func content(_ img: CollageImage) -> some View {
        if state.isFindingSubject(img.id) || state.subjectMask(for: img) == nil {
            HStack(spacing: 8) {
                ProgressView()
                Text("Finding the subject…").foregroundColor(.secondary)
            }
            .font(.subheadline)
            .onAppear { state.requestSubjectMask(for: img) }
        } else if state.subjectMask(for: img)?.mask == nil {
            Text("No clear subject found in this photo.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        } else if let edges = img.protrusion {
            let crossing = state.protrudableEdges(for: img.id)
            let count = state.subjectMask(for: img)?.instances.count ?? 0
            if count > 1 {
                // Which subjects protrude — matches the numbered badges in
                // the photo (tapping a subject there does the same).
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        PackChip(title: "All", isActive: img.protrusionObjects == nil) {
                            state.setProtrusionObjects(nil, for: img.id)
                        }
                        ForEach(0..<count, id: \.self) { i in
                            PackChip(title: "\(i + 1)", isActive: img.protrusionObjects?.contains(i) ?? true) {
                                state.toggleProtrusionObject(i, for: img.id)
                            }
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                PackChip(title: "All", isActive: edges == .all) {
                    state.setProtrusion(.all, for: img.id)
                }
                ForEach(ProtrusionEdges.ordered, id: \.1) { edge, title in
                    PackChip(title: title, isActive: edges.contains(edge)) {
                        var next = edges
                        if next.contains(edge) { next.remove(edge) } else { next.insert(edge) }
                        // Unticking the last edge turns protrusion off.
                        state.setProtrusion(next.isEmpty ? nil : next, for: img.id)
                    }
                    // Dimmed: the subject doesn't reach that edge now.
                    .opacity(crossing.contains(edge) ? 1 : 0.45)
                }
            }
            HStack(spacing: 8) {
                Text("Effect")
                    .font(.subheadline)
                Picker("Effect", selection: Binding(
                    get: { img.protrusionEffect },
                    set: { state.setProtrusionEffect($0, for: img.id) })) {
                    ForEach(ProtrusionEffect.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            Text(hint(img, crossing: crossing))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func hint(_ img: CollageImage, crossing: ProtrusionEdges) -> String {
        if crossing.isEmpty {
            return "The subject sits fully inside the box. Zoom or move the photo so the box cuts it off — that part will break out."
        }
        if (state.subjectMask(for: img)?.instances.count ?? 0) > 1, img.protrusionObjects == nil {
            return "Tap a subject in the photo to leave it out (or use the numbers)."
        }
        if img.protrusionEffect == .border, state.borderThickness <= 0 {
            return "Border follows the Layout border (color, thickness, pattern) — set a thickness there to see it."
        }
        return "Dimmed edges: the subject doesn't reach them right now."
    }
}
