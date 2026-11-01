import SwiftUI
import TipKit

/// Glass dialog shown while the collage is being exported, with a progress
/// bar (per-page progress for multi-page exports).
struct SavingOverlay: View {
    @EnvironmentObject var state: CollageState

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()

            VStack(spacing: 14) {
                Text("Exporting")
                    .font(.headline)
                    .foregroundColor(.primary)

                if state.exportTotalPages > 1 {
                    ProgressView(value: state.exportProgress)
                        .progressViewStyle(.linear)
                        .tint(.accentColor)
                        .frame(width: 200)
                    Text("\(Int(state.exportProgress * 100))%")
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(.secondary)
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.accentColor)
                }
                Button("Cancel") { state.exportCancelRequested = true }
                    .font(.subheadline.weight(.semibold))
                    .disabled(state.exportCancelRequested)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(ColorManager.glassStroke, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 24, y: 10)
        }
    }
}

/// A pill at the top of the screen while canvas touches edit the overlay,
/// not the collage — so photos that won't move never look broken. Purely
/// informational: touches pass through.
/// The glass behind the toolbar's controls: Liquid Glass where there is
/// some, a thin material before.
private struct ToolbarPillGlass: View {
    var body: some View {
        if #available(iOS 26, macOS 26, *) {
            Color.clear.glassEffect(.regular, in: Capsule())
        } else {
            Capsule().fill(.ultraThinMaterial)
                .overlay(Capsule().strokeBorder(ColorManager.glassStroke, lineWidth: 0.8))
        }
    }
}

/// The phone's action bar, just above the tabs (or the open panel): undo
/// and redo on the left, the pager in the middle, compare, full screen and
/// export on the right — in thumb reach, with no toolbar over the collage.
/// In overlay mode the OVERLAY MODE band takes its place.
struct ActionBar: View {
    @EnvironmentObject var state: CollageState
    static let height: CGFloat = 44

    var body: some View {
        ZStack {
            if state.overlayModeActive {
                OverlayModeLabel()
                    .frame(width: state.canvasShownWidth > 0 ? state.canvasShownWidth : nil)
                    .transition(.opacity)
            } else {
                HStack(spacing: 8) {
                    // Only what can be used now: undo / redo while there's
                    // something to undo / redo, compare while there are edits.
                    if state.canUndo || state.canRedo {
                        HStack(spacing: 0) {
                            if state.canUndo { historyButton("arrow.uturn.backward", "Undo") { state.undo() } }
                            // Both there: a thin line between them.
                            if state.canUndo && state.canRedo {
                                Rectangle()
                                    .fill(Color.primary.opacity(0.25))
                                    .frame(width: 1, height: 20)
                            }
                            if state.canRedo { historyButton("arrow.uturn.forward", "Redo") { state.redo() } }
                        }
                        // No side padding: one button alone sits in a
                        // perfect circle (40 × 40).
                        .frame(height: 40)
                        .background { ToolbarPillGlass() }
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 0) {
                        if state.slides > 1 { SpreadZoomButton() }
                        if state.hasLookEdits { CompareButton().transition(.opacity) }
                        Button { state.enterFullScreen() } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                                .frame(width: 40, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Full screen")
                    }
                    .padding(.horizontal, 3)
                    .frame(height: 40)
                    .background { ToolbarPillGlass() }
                }
                // The pager in the middle of the row, whatever the sides hold.
                .overlay {
                    PageTabBar()
                }
                .transition(.opacity)
            }
        }
        .frame(height: Self.height)
        .animation(.easeInOut(duration: 0.2), value: state.overlayModeActive)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: state.canUndo)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: state.canRedo)
        .animation(.easeInOut(duration: 0.2), value: state.hasLookEdits)
    }

    private func historyButton(_ sf: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: sf)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.primary)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct OverlayModeLabel: View {
    private static let title = "OVERLAY MODE"
    private static let note = "Gestures move overlays, not photos"
    /// Letter spacing that makes the title as wide as the note under it.
    /// Tracking also follows the last letter, so the title is nudged back
    /// by half of it to stay centered.
    private static let tracking: CGFloat = {
        #if canImport(UIKit)
        func width(_ text: String, _ size: CGFloat, _ weight: UIFont.Weight) -> CGFloat {
            (text as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: size, weight: weight)]).width
        }
        #else
        func width(_ text: String, _ size: CGFloat, _ weight: NSFont.Weight) -> CGFloat {
            (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight)]).width
        }
        #endif
        let gaps = CGFloat(title.count - 1)
        return max((width(note, 13, .medium) - width(title, 20, .heavy)) / gaps, 0)
    }()

    /// The first time overlay mode turns on after launch, a light sweeps
    /// across the band once to draw the eye; after that it just appears.
    private static var introduced = false
    @State private var sweep: CGFloat = 0
    @State private var glow = false

    var body: some View {
        VStack(spacing: 0) {
            Text(Self.title)
                .font(.system(size: 20, weight: .heavy))
                .tracking(Self.tracking)
                .offset(x: Self.tracking / 2)
            Text(Self.note)
                .font(.system(size: 13, weight: .medium))
                .opacity(0.85)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, minHeight: 32, maxHeight: .infinity)
        // A band from edge to edge: the accent, a little deeper, so the
        // white letters stand out.
        .background(Color.accentColor.overlay(Color.black.opacity(glow ? 0 : 0.25)))
        .overlay {
            GeometryReader { g in
                let band = g.size.width * 0.4
                LinearGradient(colors: [.clear, .white.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: band)
                    .offset(x: -band + sweep * (g.size.width + band))
            }
        }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12, style: .continuous))
        .onAppear {
            guard !Self.introduced else { return }
            Self.introduced = true
            withAnimation(.easeInOut(duration: 0.9).delay(0.25)) { sweep = 1 }
            withAnimation(.easeOut(duration: 0.35).delay(0.25)) { glow = true }
            withAnimation(.easeIn(duration: 0.5).delay(0.9)) { glow = false }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}

extension ContentView {
    /// Overlay mode, in its own row above the canvas (sideways; upright it
    /// takes the toolbar's place): why the photos don't move.
    @ViewBuilder
    var overlayModeRow: some View {
        if state.overlayModeActive && state.hasAnyImages && !state.toolbarHidden {
            OverlayModeLabel()
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

/// Tab control above the canvas: one numbered chip per page plus an add
/// button. Hidden while the collage has a single page.
/// Selection works by touch-and-scrub: press a chip and slide the finger
/// across others — the selection (and canvas) follows the finger live,
/// with a light haptic tick per change.
struct PageTabBar: View {
    @EnvironmentObject var state: CollageState
    @Environment(\.colorScheme) private var colorScheme
    /// Posts stepped by the drag in progress.
    @State private var scrubbed = 0
    /// Finger travel per post when swiping along the pager.
    private static let scrubStep: CGFloat = 22

    var body: some View {
        if state.pictureCount > 1 {
            let count = state.pictureCount
            let first = state.firstPicture(ofPage: state.safePageIndex)
            let whole = state.slides > 1 && state.focusedSlide == nil
            let current = state.currentPicture
            HStack(spacing: 10) {
                stepButton(system: "chevron.left", enabled: state.canStepPost(-1)) { state.stepPost(-1) }
                .accessibilityLabel("Previous post")
                // Dots, one per post.
                PictureDots(whole: whole)
                    .frame(minWidth: 44, minHeight: 26)
                    .accessibilityElement()
                    .accessibilityLabel(whole
                        ? "Posts \(first + 1) to \(first + state.slides) of \(count), page \(state.safePageIndex + 1)"
                        : "Post \(current + 1) of \(count), page \(state.safePageIndex + 1)")
                    .accessibilityAdjustableAction { d in
                        state.stepPost(d == .increment ? 1 : -1)
                    }
                stepButton(system: "chevron.right", enabled: state.canStepPost(1)) { state.stepPost(1) }
                .accessibilityLabel("Next post")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule(style: .continuous).strokeBorder(ColorManager.glassStroke, lineWidth: 1))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            )
            .animation(.easeInOut(duration: 0.2), value: current)
            // Swipe anywhere on the pager to step through the posts (left =
            // next, as on the canvas); the arrows still take taps.
            .contentShape(Capsule(style: .continuous))
            .simultaneousGesture(DragGesture(minimumDistance: 6)
                .onChanged { v in
                    let steps = Int((-v.translation.width / Self.scrubStep).rounded(.towardZero))
                    guard steps != scrubbed else { return }
                    // One post per event: the next waits for this one to land.
                    let dir = steps > scrubbed ? 1 : -1
                    scrubbed += dir
                    state.stepPost(dir)
                }
                .onEnded { _ in scrubbed = 0 })
            // Hold for the page menu.
            .contextMenu { pageMenu }
        }
    }

    /// Copy / paste the page's settings, and remove the page.
    @ViewBuilder private var pageMenu: some View {
        let page = state.currentPageIndex + 1
        Section("Page \(page) Settings") {
            Button { state.copyPageLook() } label: {
                Label("Copy Settings", systemImage: "doc.on.doc")
            }
            Button {
                state.pasteToAllOthers = false
                state.showPastePageLook = true
            } label: {
                Label(state.copiedPageNumber.map { "Paste Settings from Page \($0)…" } ?? "Paste Settings…",
                      systemImage: "doc.on.clipboard")
            }
            .disabled(state.copiedPageLook == nil)
            Button {
                state.copyPageLook()
                state.pasteToAllOthers = true
                state.showPastePageLook = true
            } label: {
                Label("Copy to Other Pages…", systemImage: "square.on.square")
            }
        }
        Button(role: .destructive) {
            state.deletePage(at: state.currentPageIndex)
        } label: {
            Label("Remove Page \(page)", systemImage: "trash")
        }
    }

    private func stepButton(system: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // Quiet, in the inactive dots' grey (lighter on a dark screen,
            // where the same grey all but disappears).
            Image(systemName: system)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color.primary.opacity(enabled ? PictureDots.idleOpacity(colorScheme)
                                                               : (colorScheme == .dark ? 0.25 : 0.12)))
                .frame(width: 30, height: 26)
                // A finger-sized touch area (44 pt) around the small arrow.
                .contentShape(Rectangle().inset(by: -9))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

}

/// A dot per post, Instagram style: the one on screen (or the whole page
/// shown) bigger and solid, a spread page's dots joined on one bar.
/// Past `window` posts only those around the current one show, the outer
/// ones shrinking where more follow.
struct PictureDots: View {
    @EnvironmentObject var state: CollageState
    @Environment(\.colorScheme) private var colorScheme
    let whole: Bool
    static let window = 9

    /// The grey of dots not on screen (and of the arrows).
    static func idleOpacity(_ scheme: ColorScheme) -> Double { scheme == .dark ? 0.6 : 0.35 }

    var body: some View {
        let count = state.pictureCount
        let first = state.firstPicture(ofPage: state.safePageIndex)
        let onScreen = whole ? first..<(first + state.slides) : state.currentPicture..<(state.currentPicture + 1)
        let shown: Range<Int> = {
            guard count > Self.window else { return 0..<count }
            let center = (onScreen.lowerBound + onScreen.upperBound - 1) / 2
            let start = min(max(center - Self.window / 2, 0), count - Self.window)
            return start..<(start + Self.window)
        }()
        HStack(spacing: 5) {
            ForEach(Array(state.pages.indices), id: \.self) { pi in
                let pageFirst = state.firstPicture(ofPage: pi)
                let n = min(max(state.pages[pi].style.slides, 1), CollageState.maxSlides)
                let lo = max(pageFirst, shown.lowerBound), hi = min(pageFirst + n, shown.upperBound)
                let posts = lo < hi ? Array(lo..<hi) : []
                if !posts.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(posts, id: \.self) { k in
                            let on = onScreen.contains(k)
                            // All one size: the post on screen filled, in
                            // full strength (white on a dark screen), the
                            // others outlined rings.
                            ZStack {
                                if on {
                                    Circle().fill(Color.primary)
                                } else {
                                    Circle().strokeBorder(Color.primary.opacity(Self.idleOpacity(colorScheme)),
                                                          lineWidth: 1.3)
                                }
                            }
                            .frame(width: 8, height: 8)
                        }
                    }
                    .padding(n > 1 ? 2 : 0)
                    .background {
                        if n > 1 { Capsule().fill(Color.primary.opacity(colorScheme == .dark ? 0.2 : 0.12)) }
                    }
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: shown)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: onScreen)
    }
}

/// The open collage couldn't be saved (the phone is full, say): said
/// until a save goes through, with a way to try again.
struct SaveFailedBanner: View {
    @EnvironmentObject var state: CollageState

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text("Couldn't save this collage")
                    .font(.subheadline.weight(.semibold))
                Text("Free up space on your iPhone, then try again.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 4)
            Button("Retry") {
                state.hasUnsavedChanges = true
                state.saveProjectNow()
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .accessibilityElement(children: .combine)
    }
}

/// Sweeps a diagonal light highlight across its content while `active`,
/// masked to the content's shape — a "work in progress" shimmer.
struct Shimmer: ViewModifier {
    let active: Bool
    @State private var phase: CGFloat = -1
    @State private var visible = false
    /// Not while the app is away: the endless sweep stops (its layer goes).
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .overlay {
                if visible {
                    GeometryReader { geo in
                        let w = geo.size.width
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .white.opacity(0.85), location: 0.5),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing)
                            .frame(width: w * 0.45)
                            .rotationEffect(.degrees(20))
                            .offset(x: phase * w * 1.6)
                            .blendMode(.plusLighter)
                    }
                    .allowsHitTesting(false)
                }
            }
            .mask(content)
            // Only reveal the shimmer once an action has run past ~0.5s, so
            // quick operations don't flash it — only genuinely slow ones
            // (like importing images) show the indicator.
            .task(id: active && scenePhase == .active) {
                guard active, scenePhase == .active else { visible = false; return }
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                phase = -1
                visible = true
                withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmering(_ active: Bool) -> some View { modifier(Shimmer(active: active)) }
}

struct ContentView: View {
    @EnvironmentObject var state: CollageState
    @Environment(\.colorScheme) var colorScheme

    // Global-space frames of the ratio popup and its toolbar button, so a tap
    // anywhere else on screen can close the popup (the button keeps its own
    // toggle behavior).
    @State private var ratioPanelFrame: CGRect = .zero
    /// Global top of the canvas area and bottom of the pager, which limit
    /// how tall the panel may grow.
    @State private var canvasTopY: CGFloat = 0
    @State private var pagerBottomY: CGFloat = 0

    private struct PanelLimitKey: Equatable {
        let canvasTop: CGFloat, pagerBottom: CGFloat, pages: Int
    }
    @State private var ratioButtonFrame: CGRect = .zero

    var body: some View {
        Group {
            #if os(macOS)
            macLayout
            #else
            // Upright (a phone, or an iPad held upright): collage above,
            // panel below. Anything wider than tall (a phone held sideways,
            // an iPad held sideways) gets two columns — collage left,
            // controls right. Decided by the actual shape, not the size
            // class, which reports some phones' landscape as compact.
            GeometryReader { geo in
                let upright = geo.size.width <= geo.size.height
                Group {
                    if upright { iPhoneLayout } else { iPadLayout }
                }
                .environment(\.phoneLayout, upright)
            }
            #endif
        }
        #if DEBUG
        .overlay(alignment: .topLeading) {
            if UITest.isOn { UITestProbe() }
        }
        #endif
        .alert("Export", isPresented: Binding(get: { state.exportProblem != nil },
                                             set: { if !$0 { state.exportProblem = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(state.exportProblem ?? "")
        }
        // First-run tips (see Tips.swift).
        .task { await CollageTips.follow() }
        // Tips wait until a new collage has settled on screen (a popover
        // presented while the panel slides in is asking for trouble).
        .onChange(of: state.hasAnyImages, initial: true) { _, has in
            guard has else { CollageTips.hasImages = false; return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if state.hasAnyImages { CollageTips.hasImages = true }
            }
        }
        .onChange(of: state.selectedImageId) { _, id in
            if id != nil { PhotoMenuTip().invalidate(reason: .actionPerformed) }
        }
        // The selection belongs to the page it was made on.
        .onChange(of: state.currentPageIndex) { _, _ in state.selectImage(nil) }
        // "Undo" / "Redo" after a shake.
        .overlay(alignment: .top) {
            HistoryToast().padding(.top, state.hasAnyImages ? 16 : 70)
        }
        .animation(.easeInOut(duration: 0.25), value: state.overlayModeActive)
        .overlay(alignment: .top) {
            if state.saveFailed && state.hasAnyImages && !state.toolbarHidden {
                SaveFailedBanner().padding(.top, 8).padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        #if canImport(UIKit)
        .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
            if state.canUndo {
                state.undo()
                state.flashHistoryToast("Undo")
            }
        }
        #endif
    }

    // MARK: - macOS / iPad landscape: sidebar + canvas

    #if os(macOS)
    var macLayout: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                PageTabBar()
                CanvasContainerView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                // The selected photo's tools (on iPhone they stand in for the tabs).
                if let image = state.selectedImage {
                    PhotoToolsRow(image: image)
                        .frame(maxWidth: 420)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: FloatingTabBar.cornerRadius, style: .continuous))
                        .background(PhotoToolsRow.background, in: RoundedRectangle(cornerRadius: FloatingTabBar.cornerRadius, style: .continuous))
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            Divider()
            SidebarView()
                .frame(width: 280)
                .background(ColorManager.windowBackground)
        }
        .frame(minWidth: 900, minHeight: 600)
        .sheet(isPresented: $state.showExportSheet, onDismiss: { state.clearExportFiles() }) { ExportSheetView().environmentObject(state) }
    }
    #endif

    /// A photo is selected (and no editor is open for it).
    private var photoTools: Bool {
        state.selectedImage != nil && state.textEditTargetId == nil && state.protrusionTargetId == nil
            && state.photoEditTargetId == nil
    }

    /// Two columns (phone or iPad held sideways): the collage on the left,
    /// the controls on the right.
    var iPadLayout: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                overlayModeRow.frame(height: 44)
                PageTabBar()
                CanvasContainerView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // The selected photo's tools, floating at the bottom of the
            // canvas (on the phone they stand in for the tabs).
            .overlay(alignment: .bottom) {
                if let image = state.selectedImage, photoTools {
                    PhotoToolsRow(image: image)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .frame(maxWidth: 480)
                        .background(PhotoToolsRow.background,
                                    in: RoundedRectangle(cornerRadius: FloatingTabBar.cornerRadius, style: .continuous))
                        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: photoTools)
            Divider()
            SidebarView()
                .frame(width: 300)
                .background(
                    { ColorManager.groupedBackground }()
                )
        }
        .sheet(isPresented: $state.showExportSheet, onDismiss: { state.clearExportFiles() }) { ExportSheetView().environmentObject(state) }
    }

    // MARK: - iPhone: canvas + bottom panel


    private var toolbar: some View {
        // Toolbar: the logo on the left and the controls on the right,
        // floating straight on the backdrop (no panel behind them).
        HStack {
            // Placeholder reserving horizontal space for the logo, which
            // is drawn as an overlay so it can spill below the toolbar.
            Color.clear.frame(width: 54, height: 1)
            Spacer()

            HStack(spacing: 0) {
                // Ratio selector — always available, even before images exist.
                Button {
                    if state.isRatioOpen { state.closeRatio() } else { state.openRatio() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "aspectratio")
                            .font(.system(size: 15, weight: .medium))
                        Text(state.ratio.rawValue.replacingOccurrences(of: ":", with: "×"))
                            .font(.footnote.weight(.bold))
                            .lineLimit(1)
                    }
                    // Plain like the other toolbar icons; accent-colored
                    // while its popup is open.
                    .foregroundColor(state.isRatioOpen ? .accentColor : .primary)
                    .padding(.horizontal, 6)
                    .frame(height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Canvas ratio, \(state.ratio.rawValue.replacingOccurrences(of: ":", with: " by "))")
                .background(
                    GeometryReader { g in
                        Color.clear.onChange(of: g.frame(in: .global), initial: true) { _, f in
                            ratioButtonFrame = f
                        }
                    }
                )

                // Undo / redo, full-screen preview and Share — only once
                // there's a collage (or something to undo back to).
                if state.hasAnyImages || state.canUndo {
                    UndoRedoButtons(size: 40, compact: true)
                }
                if state.hasAnyImages {
                    // Full screen: only the collage — no status bar, toolbar,
                    // tab bar or panel. A swipe on it steps through the
                    // posts, a tap goes back to editing.
                    Button {
                        state.enterFullScreen()
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                            .frame(width: 40, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Full screen")

                    Button {
                        state.showExportOptions = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.primary)
                            .frame(width: 40, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Export")
                }
            }
            .padding(.horizontal, 5)
            .frame(height: 40)
            // The controls gathered in one compact glass pill.
            .background { ToolbarPillGlass() }
        }
        // Fixed height so the bar doesn't collapse before any images are
        // added (the icons only appear once images exist) — keeps the logo
        // clear of the system clock.
        .frame(height: 48)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        // Logo overlay: larger than the toolbar and unclipped, so it
        // spills below the bar's bottom edge.
        .overlay(alignment: .bottomLeading) {
            HStack(alignment: .bottom, spacing: 6) {
                Image("DasKolazLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 36)
                    // In color on the Collages screen; black and white while
                    // working on a collage, so it doesn't compete with it.
                    .grayscale(state.hasAnyImages ? 1 : 0)
                    .animation(.easeInOut(duration: 0.4), value: state.hasAnyImages)
                    .shimmering(state.isBusy)
                    // Tap: back to the Collages screen.
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard state.hasAnyImages else { return }
                        withAnimation(.easeInOut(duration: 0.25)) { state.goToCollages() }
                    }
                    // Press and hold: About das Kolaž (version, build, memory…).
                    .onLongPressGesture(minimumDuration: 0.6) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        state.showAbout = true
                    }
                    .accessibilityAction(named: "About das Kolaž") { state.showAbout = true }
                    .accessibilityAddTraits(state.hasAnyImages ? .isButton : [])
                    .accessibilityLabel(state.hasAnyImages ? "Collages" : "das Kolaž")
            }
            .padding(.leading, 10)
            .offset(y: -8)
        }
        // Keep the toolbar (and its spilling logo) above the canvas below
        .zIndex(1)
    }

    /// How tall the panel may grow: up to just under the pager (or the
    /// toolbar).
    private func updatePanelLimit() {
        // Room above it for the action bar over the canvas's top.
        let limit = canvasTopY + 8 + ActionBar.height + 6
        guard limit.differs(from: state.panelTopLimitY) else { return }
        Diagnostics.count("panelTopLimitY")
        state.panelTopLimitY = limit
    }

    var iPhoneLayout: some View {
        VStack(spacing: 0) {
            if !state.toolbarHidden && !state.hasAnyImages {
                // Only on the Collages screen (logo, ratio): a collage being
                // edited starts right under the status bar, its controls in
                // the action bar above the tabs.
                toolbar
                    // A thin gap above the canvas.
                    .padding(.bottom, 6)
            } else if !state.toolbarHidden {
                Color.clear.frame(height: 6)
            }
            // Ratio panel takes real layout space, so the canvas below
            // resizes and shows the chosen ratio exactly
            if state.isRatioOpen {
                RatioPanelView()
                    .padding(12)
                    // Glass card matching the bottom panel.
                    .background {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .strokeBorder(ColorManager.glassStroke, lineWidth: 0.8))
                            .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    .background(
                        GeometryReader { g in
                            Color.clear.onChange(of: g.frame(in: .global), initial: true) { _, f in
                                ratioPanelFrame = f
                            }
                        }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Canvas fills the remaining space; the controls float on top as a
            // glass panel so the canvas gets maximum room.
            VStack(spacing: 0) {
                CanvasContainerView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // The keyboard must not shrink the canvas (it slides up
                    // to keep an edited text box in view instead).
                    .ignoresSafeArea(.keyboard, edges: .bottom)
                    // Leave the tab pill's zone free so it never covers the
                    // collage; full-screen preview gives it back.
                    .padding(.bottom, state.hasAnyImages && !state.chromeHidden ? FloatingTabBar.zoneHeight : 0)
                    .animation(.easeInOut(duration: 0.25), value: state.chromeHidden)
                    // Only the collage: the whole screen, so it sits right in the middle.
                    .ignoresSafeArea(edges: state.toolbarHidden ? .vertical : [])
            }
            // Floating page counter pill over the top of the canvas.
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: state.selectedImageId)
            // The action bar, floating over the top of the canvas (where the
            // pager was); the panel stops just under it.
            .overlay(alignment: .top) {
                if state.hasAnyImages && !state.chromeHidden {
                    ActionBar()
                        .padding(.horizontal, 12)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { f in
                            guard f.differs(from: state.pagerFrame) else { return }
                            Diagnostics.count("pagerFrame")
                            state.pagerFrame = f
                        }
                        .onDisappear { state.pagerFrame = .zero }
                        .panelChrome(state)
                        .transition(.opacity)
                }
            }
            // The panel may grow up to just under the pager (or the toolbar).
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { canvasTopY = $0 }
            .onChange(of: PanelLimitKey(canvasTop: canvasTopY, pagerBottom: pagerBottomY, pages: state.pages.count),
                      initial: true) { _, _ in updatePanelLimit() }
            .overlay(alignment: .bottom) {
                // No chrome until there are images — the empty canvas just
                // shows the big "add images" button.
                if state.hasAnyImages && !state.chromeHidden {
                    ZStack(alignment: .bottom) {
                        // The panel card, positioned by the shared interactive
                        // offset (0 = open, panelHeight = fully hidden). It
                        // slides down behind the tab pill.
                        // Clipped at the pill's bottom edge, so it rises out
                        // of the toolbar instead of sliding past it.
                        BottomPanelView()
                            .background(
                                GeometryReader { g in
                                    // Not per frame while the grabber is dragged
                                    // (it would redraw the whole app); once at the end.
                                    Color.clear
                                        .onChange(of: g.frame(in: .global).minY, initial: true) { _, y in
                                            guard !state.isPanelDragging else { return }
                                            let top = state.isPanelOpen ? y : 0
                                            guard top.differs(from: state.panelTopGlobalY) else { return }
                                            Diagnostics.count("panelTopGlobalY")
                                            state.panelTopGlobalY = top
                                        }
                                        .onChange(of: state.isPanelDragging) { _, dragging in
                                            guard !dragging else { return }
                                            state.panelTopGlobalY = state.isPanelOpen ? g.frame(in: .global).minY : 0
                                        }
                                }
                            )
                            .padding(.horizontal, 10)
                            // The thin strips beside the card belong to the
                            // panel too: a swipe that strays there must not
                            // reach the photo underneath (whose pan closes
                            // the panel).
                            .background(Color.black.opacity(0.001).padding(.top, 8))
                            .padding(.bottom, FloatingTabBar.zoneHeight - FloatingTabBar.bottomMargin
                                     + (state.isPanelOpen && state.panelDrag == 0 ? FloatingTabBar.openLift : 0))
                            .animation(.easeInOut(duration: 0.25), value: state.isPanelOpen)
                            .offset(y: state.panelOffset)
                            .padding(.top, 40)      // room for the card's shadow inside the clip
                            // The clip follows the pill's rounded bottom
                            // corners, so nothing shows past them; above the
                            // pill it is the full width (keeps the shadow).
                            .mask {
                                ZStack(alignment: .bottom) {
                                    Rectangle().padding(.bottom, 60)
                                    RoundedRectangle(cornerRadius: FloatingTabBar.cornerRadius, style: .continuous)
                                        .padding(.horizontal, 10)
                                        .frame(height: 140)
                                }
                            }
                            .padding(.bottom, FloatingTabBar.bottomMargin)

                        FloatingTabBar(merged: state.isPanelOpen && state.panelDrag == 0)
                            .panelChrome(state)
                            .popoverTip(TabBarTip(), arrowEdge: .bottom)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        // Full screen: a sideways swipe steps to the previous / next post,
        // a tap goes back to editing; nothing underneath reacts.
        .overlay {
            if state.toolbarHidden {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { g in
                                let dx = g.translation.width, dy = g.translation.height
                                if abs(dx) < 10 && abs(dy) < 10 {
                                    state.exitFullScreen()
                                } else if abs(dx) > 40 && abs(dx) > abs(dy) {
                                    state.stepPost(dx < 0 ? 1 : -1)
                                }
                            }
                    )
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Exit full screen")
            }
        }
        .statusBarHidden(state.toolbarHidden)
        .persistentSystemOverlays(state.toolbarHidden ? .hidden : .automatic)
        // One background tone across the whole app, including behind the
        // toolbar and status bar
        .background(ColorManager.canvasAreaBackground.ignoresSafeArea())
        // A tap ANYWHERE outside the ratio popup (and its toolbar button,
        // which keeps its own toggle) closes the popup. Simultaneous, so it
        // rides along with whatever the tap actually hit — buttons included.
        .simultaneousGesture(
            SpatialTapGesture(coordinateSpace: .global)
                .onEnded { value in
                    guard state.isRatioOpen,
                          !ratioPanelFrame.contains(value.location),
                          !ratioButtonFrame.contains(value.location) else { return }
                    state.closeRatio()
                }
        )
        .sheet(isPresented: $state.showExportSheet, onDismiss: { state.clearExportFiles() }) { ExportSheetView().environmentObject(state) }
    }
}


extension EnvironmentValues {
    /// The upright layout (collage above, tab bar and panel below), on a
    /// phone or an iPad; false for the sideways one with the sidebar.
    @Entry var phoneLayout = true
}
