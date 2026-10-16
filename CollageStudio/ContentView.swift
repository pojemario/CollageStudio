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

/// Edge-to-edge strip above the tab pill: canvas touches currently edit
/// the overlay, not the collage. Purely informational — touches pass through.
struct OverlayModeLabel: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .semibold))
            Text("OVERLAY mode: zoom and rotate overlay")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.5))
        .allowsHitTesting(false)
    }
}

/// Tab control above the canvas: one numbered chip per page plus an add
/// button. Hidden while the collage has a single page.
/// Selection works by touch-and-scrub: press a chip and slide the finger
/// across others — the selection (and canvas) follows the finger live,
/// with a light haptic tick per change.
struct PageTabBar: View {
    @EnvironmentObject var state: CollageState

    var body: some View {
        if state.pages.count > 1 {
            HStack(spacing: 12) {
                stepButton(system: "chevron.left", enabled: state.currentPageIndex > 0) {
                    select(state.currentPageIndex - 1)
                }
                .accessibilityLabel("Previous page")
                // Tap the page number for the page menu.
                Menu { pageMenu } label: {
                    Text("\(state.currentPageIndex + 1) / \(state.pages.count)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundColor(.primary)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Page \(state.currentPageIndex + 1) of \(state.pages.count)")
                .accessibilityHint("Opens the page menu")
                stepButton(system: "chevron.right", enabled: state.currentPageIndex < state.pages.count - 1) {
                    select(state.currentPageIndex + 1)
                }
                .accessibilityLabel("Next page")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule(style: .continuous).strokeBorder(ColorManager.glassStroke, lineWidth: 1))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            )
            // Long-press works too.
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
            Image(systemName: system)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(enabled ? .primary : .secondary.opacity(0.4))
                .frame(width: 30, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func select(_ index: Int) {
        guard state.pages.indices.contains(index) else { return }
        // Choosing a page from the top bar also dismisses the bottom panel.
        state.collapsePanel()
        state.goToPage(index)
        #if canImport(UIKit)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
    }
}

/// Sweeps a diagonal light highlight across its content while `active`,
/// masked to the content's shape — a "work in progress" shimmer.
struct Shimmer: ViewModifier {
    let active: Bool
    @State private var phase: CGFloat = -1
    @State private var visible = false

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
            .task(id: active) {
                guard active else { visible = false; return }
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
    @Environment(\.horizontalSizeClass) var hSizeClass
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
            // Upright phone: collage above, panel below. Anything wider than
            // tall (a phone held sideways, any iPad) gets two columns —
            // collage left, controls right. Decided by the actual shape, not
            // the size class, which reports some phones' landscape as compact.
            GeometryReader { geo in
                if hSizeClass == .compact && geo.size.width <= geo.size.height {
                    iPhoneLayout
                } else {
                    iPadLayout
                }
            }
            #endif
        }
        // Topmost: the long-press image menu floats above every panel.
        .overlay { BoxActionMenuLayer() }
        // Redo, dropped down below the toolbar's Undo button.
        .overlay { RedoBubbleLayer() }
        // First-run tips (see Tips.swift).
        .task { await CollageTips.follow() }
        .onChange(of: state.hasAnyImages, initial: true) { _, has in CollageTips.hasImages = has }
        .onChange(of: state.showBoxActionMenu) { _, open in
            if open { PhotoMenuTip().invalidate(reason: .actionPerformed) }
        }
        // "Undo" / "Redo" after a shake.
        .overlay(alignment: .top) {
            HistoryToast().padding(.top, 70)
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
            }
            Divider()
            SidebarView()
                .frame(width: 280)
                .background(ColorManager.windowBackground)
        }
        .frame(minWidth: 900, minHeight: 600)
        .sheet(isPresented: $state.showExportSheet) { ExportSheetView().environmentObject(state) }
    }
    #endif

    /// Two columns (phone held sideways, iPad): the collage on the left,
    /// the controls on the right.
    var iPadLayout: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                PageTabBar()
                CanvasContainerView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            SidebarView()
                .frame(width: 280)
                .background(
                    { ColorManager.groupedBackground }()
                )
        }
        .sheet(isPresented: $state.showExportSheet) { ExportSheetView().environmentObject(state) }
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
                    .frame(height: 40)
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
                    UndoRedoButtons(size: 34, compact: true)
                }
                if state.hasAnyImages {
                    ResetSettingsButton()
                }
                if state.hasAnyImages {
                    // One button, three states: editing → full-screen preview
                    // (no tab bar or panel) → only the collage (see
                    // toolbarHidden), where a tap anywhere returns to editing.
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            if state.chromeHidden {
                                state.closeRatio()
                                state.toolbarHidden = true
                            } else {
                                state.chromeHidden = true
                                state.collapsePanel()
                            }
                        }
                    } label: {
                        Image(systemName: state.chromeHidden
                              ? "arrow.up.and.down.and.arrow.left.and.right"
                              : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(state.chromeHidden ? .accentColor : .primary)
                            .frame(width: 34, height: 40)
                            .contentShape(Rectangle())
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(state.chromeHidden ? "Show only the collage" : "Full screen preview")

                    Button {
                        state.showExportOptions = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.primary)
                            .frame(width: 34, height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Export")
                }
            }
            .padding(.horizontal, 5)
            .frame(height: 44)
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
                    .accessibilityAddTraits(state.hasAnyImages ? .isButton : [])
                    .accessibilityLabel(state.hasAnyImages ? "Collages" : "das Kolaž")
            }
            .padding(.leading, 10)
            .offset(y: -8)
        }
        // Keep the toolbar (and its spilling logo) above the canvas below
        .zIndex(1)
    }

    var iPhoneLayout: some View {
        VStack(spacing: 0) {
            if !state.toolbarHidden {
                toolbar
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
            .overlay(alignment: .top) {
                if !state.toolbarHidden {
                    PageTabBar().padding(.top, 2)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { f in
                            pagerBottomY = f.maxY
                            state.pagerFrame = state.pages.count > 1 ? f : .zero
                        }
                        .onChange(of: state.pages.count > 1) { _, shown in
                            if !shown { state.pagerFrame = .zero }
                        }
                }
            }
            // The panel may grow up to just under the pager (or the toolbar).
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { canvasTopY = $0 }
            .onChange(of: PanelLimitKey(canvasTop: canvasTopY, pagerBottom: pagerBottomY, pages: state.pages.count),
                      initial: true) { _, k in
                state.panelTopLimitY = (k.pages > 1 ? max(k.pagerBottom, k.canvasTop) : k.canvasTop) + 8
            }
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
                                            state.panelTopGlobalY = state.isPanelOpen ? y : 0
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
                            // In overlay mode an "OVERLAY" label floats above
                            // the pill, so a frozen collage never looks broken.
                            .overlay(alignment: .top) {
                                if state.overlayModeActive && state.panelHiddenFraction > 0.5 {
                                    OverlayModeLabel()
                                        .offset(y: -34)
                                        .transition(.opacity)
                                }
                            }
                            .animation(.easeInOut(duration: 0.2), value: state.overlayModeActive)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        // Only the collage: a tap anywhere goes back to editing, and
        // nothing underneath reacts.
        .overlay {
            if state.toolbarHidden {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            state.toolbarHidden = false
                            state.chromeHidden = false
                        }
                    }
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
        .sheet(isPresented: $state.showExportSheet) { ExportSheetView().environmentObject(state) }
        .overlay {
            if state.isExporting {
                /*
                ProgressView("Exporting…")
                    .padding(24)
                    .background(.regularMaterial)
                    .cornerRadius(14)
                 */
            }
        }
    }
}

/// Clears every setting of the open collage back to its default; the
/// photos stay. No confirmation — Undo brings the settings back. With
/// several pages it's a menu: all pages, or just the one on screen.
/// Dimmed while nothing differs.
struct ResetSettingsButton: View {
    @EnvironmentObject var state: CollageState

    var body: some View {
        let enabled = state.hasSettingsChanges
        Group {
            if state.pages.count > 1 {
                Menu {
                    Button("Reset All Pages", systemImage: "square.stack") { reset(currentPageOnly: false) }
                    Button("Reset Page \(state.currentPageIndex + 1) Only", systemImage: "square") { reset(currentPageOnly: true) }
                } label: { icon(enabled) }
            } else {
                Button { reset(currentPageOnly: false) } label: { icon(enabled) }
            }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel("Reset all settings")
    }

    /// Sliders with a turn-back arrow: settings back to default (iOS 18+;
    /// plain sliders before that).
    private static let symbol: String = {
        let name = "slider.horizontal.2.arrow.trianglehead.counterclockwise"
        #if canImport(UIKit)
        return UIImage(systemName: name) != nil ? name : "slider.horizontal.3"
        #else
        return name
        #endif
    }()

    private func icon(_ enabled: Bool) -> some View {
        Image(systemName: Self.symbol)
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(enabled ? .primary : .secondary.opacity(0.35))
            .frame(width: 34, height: 40)
            .contentShape(Rectangle())
    }

    private func reset(currentPageOnly: Bool) {
        withAnimation(.easeInOut(duration: 0.25)) { state.resetAllSettings(currentPageOnly: currentPageOnly) }
    }
}
