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

/// Glass handle shown when the bottom panel is collapsed. A single tap on the
/// sliders icon opens the panel, with a little ripple/pulse animation.
struct PanelHandleButton: View {
    @EnvironmentObject var state: CollageState
    @State private var tapCount = 0

    private func open() {
        tapCount += 1
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { state.isPanelOpen = true }
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    var body: some View {
        // A circular glass button floating just above the bottom edge — reads
        // clearly as tappable. A single tap opens the panel.
        Button(action: open) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 54, height: 54)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                        // Soft white glow.
                        .shadow(color: Color.white.opacity(0.7), radius: 10)
                        .shadow(color: Color.white.opacity(0.4), radius: 20)
                )
                .contentShape(Circle())
                // A quick pulse of the whole button on tap.
                .modifier(TapPulse(trigger: tapCount))
        }
        .buttonStyle(.plain)
    }
}

/// Briefly scales its content up then back on each `trigger` change.
private struct TapPulse: ViewModifier {
    let trigger: Int
    @State private var pulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(pulsing ? 1.18 : 1.0)
            .onChange(of: trigger) { _, _ in
                pulsing = true
                withAnimation(.spring(response: 0.35, dampingFraction: 0.45)) { pulsing = false }
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
        withAnimation(.easeInOut(duration: 0.15)) { state.currentPageIndex = index }
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
            // Toolbar
            HStack {
                // Placeholder reserving horizontal space for the logo, which
                // is drawn as an overlay so it can spill below the toolbar.
                Color.clear.frame(width: 77, height: 1)
                Spacer()

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
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(Capsule().fill(Color.white.opacity(0.18)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)

                // Full-screen toggle and Share — only once there are images.
                if state.hasAnyImages {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            state.isPanelOpen.toggle()
                        }
                    } label: {
                        Image(systemName: state.isPanelOpen
                              ? "arrow.up.left.and.arrow.down.right"
                              : "arrow.down.right.and.arrow.up.left")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.white)
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
                            .font(.system(size: 19, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            // Fixed height so the bar doesn't collapse before any images are
            // added (the icons only appear once images exist) — keeps the logo
            // clear of the system clock.
            .frame(height: 40)
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            // Black bar extending up behind the status bar; icons are white.
            .background(Color.black.ignoresSafeArea(edges: .top))
            // Logo overlay: larger than the toolbar and unclipped, so it
            // spills below the bar's bottom edge.
            .overlay(alignment: .bottomLeading) {
                Image("DasKolazLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 48)
                    .shimmering(state.isBusy)
                    .padding(.leading, 12)
                    .offset(y: 3)
                    .allowsHitTesting(false)
            }
            // Keep the toolbar (and its spilling logo) above the canvas below
            .zIndex(1)
            // Ratio panel takes real layout space, so the canvas below
            // resizes and shows the chosen ratio exactly
            if state.isRatioOpen {
                RatioPanelView()
                    .padding(12)
                    // Very transparent glass, square (unrounded) corners.
                    .background {
                        Rectangle()
                            .fill(.ultraThinMaterial)
                            .opacity(0.5)
                            .overlay(Rectangle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                            .shadow(color: .black.opacity(0.15), radius: 12, y: 2)
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Canvas fills the remaining space; the controls float on top as a
            // glass panel so the canvas gets maximum room.
            VStack(spacing: 0) {
                CanvasContainerView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // Floating page counter pill over the top of the canvas.
            .overlay(alignment: .top) {
                PageTabBar().padding(.top, 2)
            }
            .overlay(alignment: .bottom) {
                // No panel until there are images — the empty canvas just
                // shows the big "add images" button.
                if state.hasAnyImages {
                    ZStack(alignment: .bottom) {
                        // Collapsed handle — a circular button floating above
                        // the bottom edge that fades out as the panel rises.
                        PanelHandleButton()
                            .padding(.bottom, 10)
                            .opacity(state.panelHiddenFraction)
                            .allowsHitTesting(state.panelHiddenFraction > 0.5)
                        // The panel, positioned by the shared interactive
                        // offset (0 = open, panelHeight = fully hidden).
                        BottomPanelView()
                            .offset(y: state.panelOffset)
                            .ignoresSafeArea(edges: .bottom)
                    }
                }
            }
        }
        // One background tone across the whole app, including behind the
        // toolbar and status bar
        .background(ColorManager.canvasAreaBackground.ignoresSafeArea())
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
