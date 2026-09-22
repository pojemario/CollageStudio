import SwiftUI

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
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
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
                Text("\(state.currentPageIndex + 1) / \(state.pages.count)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundColor(.primary)
                stepButton(system: "chevron.right", enabled: state.currentPageIndex < state.pages.count - 1) {
                    select(state.currentPageIndex + 1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            )
            // Long-press to delete the current page.
            .contextMenu {
                Button(role: .destructive) {
                    state.deletePage(at: state.currentPageIndex)
                } label: {
                    Label("Delete Page \(state.currentPageIndex + 1)", systemImage: "trash")
                }
            }
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
    @State private var ratioButtonFrame: CGRect = .zero

    var body: some View {
        #if os(macOS)
        macLayout
        #else
        if hSizeClass == .compact {
            iPhoneLayout
        } else {
            iPadLayout
        }
        #endif
    }

    // MARK: - macOS / iPad landscape: sidebar + canvas

    #if os(macOS)
    var macLayout: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 280)
                .background(ColorManager.windowBackground)
            Divider()
            VStack(spacing: 0) {
                PageTabBar()
                CanvasContainerView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .sheet(isPresented: $state.showExportSheet) { ExportSheetView().environmentObject(state) }
    }
    #endif

    var iPadLayout: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 280)
                .background(
                    { ColorManager.groupedBackground }()
                )
            Divider()
            VStack(spacing: 0) {
                PageTabBar()
                CanvasContainerView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $state.showExportSheet) { ExportSheetView().environmentObject(state) }
    }

    // MARK: - iPhone: canvas + bottom panel


    var iPhoneLayout: some View {
        VStack(spacing: 0) {
            // Toolbar: the logo on the left and a glass cluster of controls
            // on the right, floating straight on the backdrop.
            HStack {
                // Placeholder reserving horizontal space for the logo, which
                // is drawn as an overlay so it can spill below the toolbar.
                Color.clear.frame(width: 77, height: 1)
                Spacer()

                HStack(spacing: 2) {
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
                        .foregroundColor(state.isRatioOpen ? .white : .primary)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(
                            Capsule().fill(state.isRatioOpen ? Color.accentColor : Color.primary.opacity(0.07))
                        )
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .background(
                        GeometryReader { g in
                            Color.clear.onChange(of: g.frame(in: .global), initial: true) { _, f in
                                ratioButtonFrame = f
                            }
                        }
                    )

                    // Full-screen preview and Share — only once there are images.
                    if state.hasAnyImages {
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                state.chromeHidden.toggle()
                                if state.chromeHidden { state.collapsePanel() }
                            }
                        } label: {
                            Image(systemName: state.chromeHidden
                                  ? "arrow.down.right.and.arrow.up.left"
                                  : "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.primary)
                                .frame(width: 40, height: 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button {
                            if state.pages.count > 1 {
                                state.showExportOptions = true
                            } else {
                                Task { await state.exportPages(allPages: false) }
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundColor(.primary)
                                .frame(width: 40, height: 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 5)
                .frame(height: 44)
                .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.6), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
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
                Image("DasKolazLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 52)
                    .shimmering(state.isBusy)
                    .padding(.leading, 10)
                    .offset(y: 2)
                    .allowsHitTesting(false)
            }
            // Keep the toolbar (and its spilling logo) above the canvas below
            .zIndex(1)
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
                                .strokeBorder(Color.white.opacity(0.55), lineWidth: 0.8))
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
            }
            // Floating page counter pill over the top of the canvas.
            .overlay(alignment: .top) {
                PageTabBar().padding(.top, 2)
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
                                    Color.clear.onChange(of: g.frame(in: .global).minY, initial: true) { _, y in
                                        state.panelTopGlobalY = state.isPanelOpen ? y : 0
                                    }
                                }
                            )
                            .padding(.horizontal, 10)
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
