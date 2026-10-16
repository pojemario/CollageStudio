import SwiftUI
#if canImport(PhotosUI)
import PhotosUI
#endif

struct SidebarView: View {
    @EnvironmentObject var state: CollageState
    @State private var showingCustom = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                logo
                if let textId = state.textEditTargetId {
                    SidebarSection(title: "Text Box") {
                        TextEditPanel(imageId: textId)
                    }
                }
                if let protrudeId = state.protrusionTargetId {
                    SidebarSection(title: "Protrude") {
                        ProtrusionPanel(imageId: protrudeId)
                    }
                }
                imagesSection
                ratioSection
                layoutSection
                framesSection
                overlaySection
                looksSection
            }
        }
        // Holds still while a photo is dragged to another page.
        .scrollDisabled(state.isMovingThumb)
    }

    // MARK: - Logo

    var logo: some View {
        HStack(spacing: 10) {
            Image("DasKolazLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 80)
                .grayscale(state.hasAnyImages ? 1 : 0)   // color only on the Collages screen
                .animation(.easeInOut(duration: 0.4), value: state.hasAnyImages)
                .shimmering(state.isBusy)
                // Tap: back to the Collages screen.
                .onTapGesture { if state.hasAnyImages { state.goToCollages() } }
                .accessibilityAddTraits(state.hasAnyImages ? .isButton : [])
                .accessibilityLabel(state.hasAnyImages ? "Collages" : "das Kolaž")
            Spacer()
            UndoRedoButtons(size: 34)
            // Export / share the collage as PNG
            Button {
                state.showExportOptions = true
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(state.hasAnyImages ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(!state.hasAnyImages)
        }
        .padding(16)
    }

    // MARK: - Images

    var imagesSection: some View {
        SidebarSection(title: "Images") {
            HStack(spacing: 8) {
                // Back to the Collages screen (the open one is saved).
                ToolbarTile(sf: "square.stack", title: "Collages", prominent: false) { state.goToCollages() }
                SpreadMenuButton(
                    // No confirmation: Undo puts the pages back.
                    onOnePerPage: { state.distributeOneImagePerPage() },
                    onAllOnOne: { state.mergeAllOntoOnePage() },
                    onBurstAll: { state.burstBalanced() })

                AddPageTile { state.addPage() }
                    .disabled(state.pages.count >= CollageState.maxPages)
                    .opacity(state.pages.count >= CollageState.maxPages ? 0.5 : 1)

                // Adds a transparent placeholder — an intentional empty slot.
                ToolbarTile(sf: "rectangle.dashed.badge.record", title: "Empty Box") { state.addEmptyImage() }

                // Adds an editable text box rendered as an image.
                ToolbarTile(sf: "character.textbox", title: "Text Box") { state.addTextImage() }
            }

            PageGroupsView()
                .padding(.top, 8)
        }
    }

    // MARK: - Ratio

    var ratioSection: some View {
        SidebarSection(title: "Canvas Ratio") {
            RatioPanelView()
        }
    }

    // MARK: - Layout

    var layoutSection: some View {
        SidebarSection(title: "Layout") {
            LayoutPanel(spacingRange: 0...40)
        }
    }

    // MARK: - Frames (adaptive frames + frame packs)

    var framesSection: some View {
        SidebarSection(title: "Frames") {
            FramesPanel()
        }
    }

    // MARK: - Overlay (dust, scratches, light leaks)

    var overlaySection: some View {
        SidebarSection(title: "Overlay") {
            OverlayPanel(inSidebar: true)
        }
    }

    // MARK: - Effects (brightness, contrast, fade, glow, …)

    var looksSection: some View {
        SidebarSection(title: "Looks") {
            LooksPanel()
        }
    }
}

// MARK: - Subviews

struct SectionDivider: View {
    var body: some View { Divider().padding(.horizontal, 0) }
}

struct SidebarSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
                .tracking(1.2)
            content
        }
        .padding(16)
        SectionDivider()
    }
}

/// Ratio chooser grid + custom size fields; shared by the sidebar section
/// and the toolbar ratio dialog.
struct RatioPanelView: View {
    @EnvironmentObject var state: CollageState

    var body: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(CanvasRatio.allCases) { r in
                    RatioButton(ratio: r, isActive: state.ratio == r) {
                        state.setRatio(r)
                    }
                }
            }
            if state.ratio == .custom {
                CustomSizeRow()
            }
        }
    }
}

struct RatioButton: View {
    let ratio: CanvasRatio
    let isActive: Bool
    let action: () -> Void

    /// Miniature of the ratio's proportions, fit into a small icon box.
    private var iconSize: CGSize {
        let maxW: CGFloat = 20
        let maxH: CGFloat = 14
        let size = ratio.canvasSize(base: 100)
        let aspect = size.width / max(size.height, 1)
        if aspect >= maxW / maxH {
            return CGSize(width: maxW, height: maxW / aspect)
        }
        return CGSize(width: maxH * aspect, height: maxH)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if ratio == .custom {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                        .frame(width: iconSize.width, height: iconSize.height)
                } else {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(lineWidth: 1.5)
                        .frame(width: iconSize.width, height: iconSize.height)
                }
                Text(ratio.rawValue.replacingOccurrences(of: ":", with: "×"))
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            // Selected: accent. Others: a touch darker than the backdrop
            // with a hairline, so they read as buttons on the glass card.
            .foregroundColor(isActive ? .white : .primary)
            .appButtonBackground(prominent: isActive)
        }
        .buttonStyle(.plain)
    }
}

/// Slider knob: machined silver. A brushed ring with a conical sheen, lit
/// from above, around a recessed center that's lit from below (as a dimple
/// would be), with a shadow inside its top edge.
struct EmbossedKnobThumb: View {
    var size: CGFloat

    var body: some View {
        let inset = size * 0.52
        ZStack {
            // Silver body, brighter at the top.
            Circle().fill(LinearGradient(colors: [Color(white: 0.97), Color(white: 0.80), Color(white: 0.66)],
                                         startPoint: .top, endPoint: .bottom))
            // Turned-metal sheen: light and dark bands around the center.
            Circle().fill(AngularGradient(
                colors: [.white.opacity(0.55), .black.opacity(0.10), .white.opacity(0.45), .black.opacity(0.14),
                         .white.opacity(0.55), .black.opacity(0.10), .white.opacity(0.45), .black.opacity(0.14),
                         .white.opacity(0.55)],
                center: .center))
                .blendMode(.overlay)
            // The recess: lit from below, its top edge in shadow.
            Circle()
                .fill(LinearGradient(colors: [Color(white: 0.62), Color(white: 0.80), Color(white: 0.95)],
                                     startPoint: .top, endPoint: .bottom)
                    .shadow(.inner(color: .black.opacity(0.45), radius: size * 0.05, y: size * 0.04)))
                .frame(width: inset, height: inset)
            // A faint sheen across the recess floor.
            Circle()
                .fill(AngularGradient(colors: [.white.opacity(0.35), .clear, .white.opacity(0.25), .clear,
                                               .white.opacity(0.35)],
                                      center: .center))
                .frame(width: inset, height: inset)
                .blendMode(.overlay)
            // Bright lip around the recess, catching light at the bottom.
            Circle()
                .strokeBorder(LinearGradient(colors: [Color.black.opacity(0.20), Color.white.opacity(0.9)],
                                             startPoint: .top, endPoint: .bottom),
                              lineWidth: 0.8)
                .frame(width: inset + 1.5, height: inset + 1.5)
            // Outer rim: lit at the top, in shade at the bottom.
            Circle().strokeBorder(
                LinearGradient(colors: [Color.white, Color(white: 0.75), Color(white: 0.45)],
                               startPoint: .top, endPoint: .bottom),
                lineWidth: 1)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

extension View {
    /// A standard slider for VoiceOver in place of a custom one. SwiftUI's
    /// Slider traps on a range with no width (Columns on a page with one
    /// photo is 1...1), so then it's a plain value instead.
    @ViewBuilder
    func accessibleSlider(value: Binding<Double>, range: ClosedRange<Double>, step: Double,
                          label: String) -> some View {
        if range.upperBound > range.lowerBound {
            accessibilityRepresentation {
                Slider(value: value, in: range, step: step) { Text(label) }
            }
        } else {
            accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
                .accessibilityValue(String(format: "%g", value.wrappedValue))
        }
    }
}

/// Custom slider: rounded gradient track, knob thumb that grows while
/// dragging, tap-anywhere to set, and light haptic ticks on step changes.
struct ModernSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    /// Called with true when a drag begins and false when it ends.
    var onEditingChanged: ((Bool) -> Void)? = nil
    /// Double-tapping the slider snaps back to this value (the Reset default).
    var resetValue: Double? = nil
    /// When set, the groove shows these colors left to right (e.g. what a
    /// hue shift turns a color into) instead of the accent value fill.
    var trackColors: [Color]? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.panelScrolls) private var panelScrolls
    @State private var isDragging = false
    /// In a scrolling panel: whether this touch went sideways (the slider's)
    /// or up/down (the scroll view's); nil until it has moved.
    @State private var claimed: Bool?
    /// This touch started on the knob: a tap there doesn't move the value,
    /// and two in a row reset it (see knobTapped).
    @State private var touchOnKnob = false
    @State private var touchStartX: CGFloat = 0
    @State private var lastKnobTap: Date = .distantPast

    private var isDark: Bool { colorScheme == .dark }

    private let thumbBase: CGFloat = 26

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let usable = max(width - thumbBase, 1)
            let span = max(range.upperBound - range.lowerBound, 0.0001)
            // Clamp so a value outside the range (or a collapsed range) can
            // never push the fill/thumb beyond the track.
            let fraction = min(max(CGFloat((value - range.lowerBound) / span), 0), 1)
            let thumbX = thumbBase / 2 + fraction * usable
            let thumbSize = isDragging ? thumbBase + 6 : thumbBase

            ZStack(alignment: .leading) {
                // Debossed metallic shell: pressed into the panel — dark upper
                // edge with an inner shadow, bright lower lip catching light
                // Soft shell: barely darker than the panel, no hard rim, so
                // the track melts into the background.
                Capsule()
                    .fill(
                        LinearGradient(colors: isDark
                                       ? [Color(white: 0.13), Color(white: 0.30)]
                                       : [Color.black.opacity(0.10), Color.black.opacity(0.04)],
                                       startPoint: .top, endPoint: .bottom)
                        .shadow(.inner(color: .black.opacity(isDark ? 0.7 : 0.16),
                                       radius: 2, y: 1))
                    )
                    .overlay(
                        Capsule().strokeBorder(Color.black.opacity(isDark ? 0.5 : 0.06), lineWidth: 0.6)
                    )
                    .frame(height: 18)

                // Recessed inner track — a subtle gray groove (not hard black)
                // with a soft inner shadow for a gentle 3D dip
                Capsule()
                    .fill(
                        LinearGradient(colors: isDark
                                       ? [Color(white: 0.22), Color(white: 0.32)]
                                       : [Color.black.opacity(0.22), Color.black.opacity(0.12)],
                                       startPoint: .top, endPoint: .bottom)
                        .shadow(.inner(color: .black.opacity(isDark ? 0.45 : 0.22),
                                       radius: 1, y: 1))
                    )
                    .frame(height: 11)
                    .padding(.horizontal, 4)

                if let trackColors {
                    Capsule()
                        .fill(LinearGradient(colors: trackColors, startPoint: .leading, endPoint: .trailing))
                        .overlay(Capsule().strokeBorder(Color.black.opacity(0.15), lineWidth: 0.6))
                        .frame(height: 12)
                        .padding(.horizontal, 4)
                } else {
                    // Value fill inside the recess
                    Capsule()
                        .fill(LinearGradient(colors: [Color.accentColor.opacity(0.55), Color.accentColor],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(thumbX - 4, 14), height: 14)
                        .padding(.leading, 4)
                }

                EmbossedKnobThumb(size: thumbSize)
                    .shadow(color: .black.opacity(0.4), radius: isDragging ? 5 : 2.5, y: 2)
                    .offset(x: thumbX - thumbSize / 2)
            }
            .frame(maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            // Drag starts instantly (no double-tap gesture competing for the
            // touch). Double-tapping the knob resets it: worked out by hand
            // from two quick taps on the knob, so dragging never waits.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if !isDragging {
                            onEditingChanged?(true)
                            touchOnKnob = abs(g.startLocation.x - thumbX) <= thumbBase / 2 + 8
                            touchStartX = g.startLocation.x
                        }
                        isDragging = true
                        // A touch on the knob only moves it once it moves.
                        if touchOnKnob && abs(g.location.x - touchStartX) < 3 { return }
                        setValue(atX: g.location.x, usable: usable, span: span)
                    }
                    .onEnded { g in
                        isDragging = false
                        if touchOnKnob && abs(g.location.x - touchStartX) < 3 { knobTapped() }
                        onEditingChanged?(false)
                    },
                including: panelScrolls ? .subviews : .all
            )
            // In a scrolling panel the slider only takes sideways drags, so a
            // swipe up or down over it scrolls instead of moving the value;
            // a tap still jumps to that spot.
            .simultaneousGesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { g in
                        if claimed == nil {
                            claimed = abs(g.translation.width) > abs(g.translation.height)
                        }
                        guard claimed == true else { return }
                        if !isDragging { onEditingChanged?(true) }
                        isDragging = true
                        setValue(atX: g.location.x, usable: usable, span: span)
                    }
                    .onEnded { _ in
                        if claimed == true {
                            isDragging = false
                            onEditingChanged?(false)
                        }
                        claimed = nil
                    },
                including: panelScrolls ? .all : .subviews
            )
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { t in
                        if abs(t.location.x - thumbX) <= thumbBase / 2 + 8 {
                            knobTapped()
                        } else {
                            setValue(atX: t.location.x, usable: usable, span: span)
                        }
                    },
                including: panelScrolls ? .all : .subviews
            )
        }
        .frame(height: 32)
        .animation(.easeOut(duration: 0.12), value: isDragging)
    }

    /// A tap on the knob; the second within a moment resets the value to
    /// its default (like double-tapping the label or the number).
    private func knobTapped() {
        let now = Date()
        defer { lastKnobTap = now }
        guard now.timeIntervalSince(lastKnobTap) < 0.35 else { return }
        lastKnobTap = .distantPast
        let target = min(max(resetValue ?? 0, range.lowerBound), range.upperBound)
        guard target != value else { return }
        value = target
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    private func setValue(atX x: CGFloat, usable: CGFloat, span: Double) {
        let f = min(max((x - thumbBase / 2) / usable, 0), 1)
        var v = range.lowerBound + Double(f) * span
        if step > 0 { v = (v / step).rounded() * step }
        v = min(max(v, range.lowerBound), range.upperBound)
        if v != value {
            value = v
            #if canImport(UIKit)
            UISelectionFeedbackGenerator().selectionChanged()
            #endif
        }
    }
}

/// True while a pull-down-to-reset over this slider group is armed: the
/// values are drawn in the accent color (see NumbersSwipeReset).
private struct ResetArmedKey: EnvironmentKey {
    static let defaultValue = false
}

/// True while the bottom panel is shorter than its content and scrolls:
/// gestures inside it then leave vertical drags to the scroll view.
private struct PanelScrollsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var resetArmed: Bool {
        get { self[ResetArmedKey.self] }
        set { self[ResetArmedKey.self] = newValue }
    }
    var panelScrolls: Bool {
        get { self[PanelScrollsKey.self] }
        set { self[PanelScrollsKey.self] = newValue }
    }
}

struct LabeledSlider: View {
    @EnvironmentObject var state: CollageState
    @Environment(\.resetArmed) private var resetArmed
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: String
    /// Double-tap reset value, forwarded to the slider.
    var resetValue: Double? = nil
    /// Wide enough for the longest label ("Temperature") on one line.
    var labelWidth: CGFloat = 92
    /// Optional color bound to a swatch circle right after the label.
    var swatchColor: Binding<Color>? = nil
    /// Keeps an empty swatch-sized slot on rows without a swatch, so they
    /// line up with rows that have one (the Layout tab). Elsewhere the
    /// slider takes that room.
    var reservesSwatchSlot = false
    /// Forwarded to the slider's track (see ModernSlider.trackColors).
    var trackColors: [Color]? = nil
    /// Shown in place of the label text (e.g. the Cols | Rows switch); the
    /// label string still names the row for focus mode.
    var customLabel: AnyView? = nil
    /// Layout's rows: a two-digit value column right at the panel's inset,
    /// so their sliders get all the spare room.
    var compactValue = false
    /// Two monospaced digits ("70"); "100" shrinks a little to fit.
    static let twoDigitValueWidth: CGFloat = 20

    var body: some View {
        HStack(spacing: 8) {
            if let customLabel {
                customLabel
                    .frame(width: labelWidth, alignment: .leading)
            } else {
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(width: labelWidth, alignment: .leading)
                    // Double-tapping the label resets to default, like the value
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { resetToDefault() }
            }
            if let swatchColor {
                ColorSwatchButton(color: swatchColor, depth: 0.55,
                                  accessibilityTitle: label == "Spacing" ? "Background color" : "\(label) color")
                    // Pure minimal in focus mode: only label + slider + value.
                    .panelChrome(state)
            } else if reservesSwatchSlot {
                Color.clear.frame(width: 24, height: 24)
            }
            ModernSlider(value: $value, range: range, step: step,
                         onEditingChanged: { editing in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                state.activeAdjustment = editing ? label : nil
                            }
                         },
                         resetValue: resetValue, trackColors: trackColors)
                // VoiceOver gets a standard slider (swipe up / down to adjust).
                .accessibleSlider(value: $value, range: range, step: step, label: label)
            Text(String(format: format, value))
                .font(.system(size: 14, weight: resetArmed ? .bold : .medium, design: .monospaced))
                .foregroundColor(resetArmed ? .accentColor : .primary.opacity(0.85))
                .lineLimit(1)
                // Longer values ("-12.5°") shrink a little to fit.
                .minimumScaleFactor(0.7)
                // Room for four characters ("-100", "-60°") unless compact,
                // hugging the slider and kept clear of the panel edge.
                .frame(width: compactValue ? Self.twoDigitValueWidth : 38, alignment: .leading)
                .padding(.trailing, compactValue ? 0 : 8)
                // Double-tapping the value also resets to default
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { resetToDefault() }
        }
        // A small "private" glass panel appears behind this row while it's the
        // one being adjusted, so its label stays readable over the canvas.
        .background { focusGlass(active: state.activeAdjustment == label) }
        // Focus mode: fade this row out when another slider is active or the
        // panel is in shuffle focus.
        .opacity(state.chromeVisible(for: label) ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: state.activeAdjustment)
    }

    private func resetToDefault() {
        value = min(max(resetValue ?? 0, range.lowerBound), range.upperBound)
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}

/// Label of the lanes slider in Layout: a two-way switch between columns
/// and rows; the slider next to it sets how many.
struct LanesSwitch: View {
    @EnvironmentObject var state: CollageState

    var body: some View {
        Picker("Lanes", selection: Binding(
            get: { state.isRows },
            set: { rows in withAnimation(.spring(response: 0.35)) { state.isRows = rows } })) {
            Text("Cols").tag(false)
            Text("Rows").tag(true)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
    }
}

/// Subtle rounded glass panel drawn behind the slider row that's currently
/// being adjusted. Extends slightly beyond the row via negative padding.
@ViewBuilder
func focusGlass(active: Bool) -> some View {
    RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
        .padding(.horizontal, -10)
        .padding(.vertical, -6)
        .opacity(active ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: active)
}

/// Horizontal sample of a border pattern, drawn with the same shapes and
/// stroke styles the real border uses.
struct BorderPatternPreview: View {
    let style: BorderStyle
    var color: Color = .primary
    var lineWidth: CGFloat = 3

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            if style.usesStamps {
                let s: CGFloat = 7
                let spacing: CGFloat
                switch style {
                case .triangles: spacing = s
                case .crosses:   spacing = s * 1.15
                default:         spacing = s * 1.5
                }
                var x = s / 2
                while x <= size.width - s / 2 {
                    let placed = StampedBorderView.stampPath(for: style, size: s)
                        .applying(CGAffineTransform(translationX: x, y: midY))
                    if style == .triangles {
                        context.fill(placed, with: .color(color))
                    } else {
                        context.stroke(placed, with: .color(color),
                                       style: StrokeStyle(lineWidth: max(1, s * 0.25), lineCap: .round))
                    }
                    x += spacing
                }
            } else {
                var line = Path()
                line.move(to: CGPoint(x: 2, y: midY))
                line.addLine(to: CGPoint(x: size.width - 2, y: midY))
                context.stroke(line, with: .color(color),
                               style: style.strokeStyle(lineWidth: lineWidth))
            }
        }
    }
}

/// Chooser for the border line pattern: shows the current pattern drawn as
/// a sample; tapping opens a popover listing every pattern, drawn.
struct BorderStylePicker: View {
    @EnvironmentObject var state: CollageState
    /// Roomier, for the Border page.
    var large = false
    @State private var showChooser = false

    var body: some View {
        Button {
            showChooser = true
        } label: {
            HStack(spacing: 4) {
                BorderPatternPreview(style: state.borderStyle)
                    .frame(width: large ? 120 : 50, height: large ? 20 : 16)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: large ? 11 : 9, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, large ? 12 : 7)
            .padding(.vertical, large ? 9 : 7)
            .appButtonBackground(prominent: false)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showChooser, arrowEdge: .bottom) {
            VStack(spacing: 2) {
                ForEach(BorderStyle.allCases) { s in
                    Button {
                        state.borderStyle = s
                        showChooser = false
                    } label: {
                        HStack(spacing: 10) {
                            BorderPatternPreview(style: s)
                                .frame(width: 110, height: 18)
                            Spacer()
                            if s == state.borderStyle {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(6)
            .frame(width: 190)
            .presentationCompactAdaptation(.popover)
        }
    }
}

/// The Layout tab: "Layout" (columns, spacing, rounding), "Border" (size,
/// color, style, position) and "Canvas" (margin, rotation).
struct LayoutPanel: View {
    @EnvironmentObject var state: CollageState
    enum Page: String, CaseIterable { case layout = "Layout", border = "Border", canvas = "Canvas" }
    /// Spacing's range (the iPad sidebar keeps a shorter one).
    var spacingRange: ClosedRange<Double> = 0...70

    var body: some View {
        VStack(spacing: 12) {
            Picker("Layout", selection: $state.layoutPage) {
                ForEach(Page.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .panelChrome(state)
            switch state.layoutPage {
            case .layout: layoutPage
            case .border: BorderPanel()
            case .canvas: canvasPage
            }
        }
    }

    private var layoutPage: some View {
        VStack(spacing: 10) {
            VStack(spacing: 10) {
                LabeledSlider(label: "Columns", value: Binding(
                    get: { Double(min(state.numCols, state.maxSelectableCols)) },
                    set: { v in state.numCols = Int(v); state.rebuildLayout(resetGrows: true) }
                ), range: 1...Double(state.maxSelectableCols), step: 1, format: "%.0f", resetValue: 2,
                   reservesSwatchSlot: true, customLabel: AnyView(LanesSwitch()),
                   compactValue: true)
                    .disabled(state.maxSelectableCols <= 1)
                    .opacity(state.maxSelectableCols <= 1 ? 0.4 : 1)
                LabeledSlider(label: "Spacing", value: $state.gap, range: spacingRange, step: 1, format: "%.0f",
                              resetValue: 10, swatchColor: $state.backgroundColor,
                              compactValue: true)
                LabeledSlider(label: "Rounding", value: $state.cornerRadius, range: 0...100, step: 1, format: "%.0f",
                              resetValue: 20, reservesSwatchSlot: true,
                              compactValue: true)
            }
            // No Reset button: swipe up or down on the labels or numbers.
            .swipeNumbersToReset(canReset: state.gap != 10 || state.cornerRadius != 20 || state.backgroundColor != .white) {
                state.gap = 10
                state.cornerRadius = 20
                state.backgroundColor = .white
            }
            .popoverTip(ResetSwipeTip(), arrowEdge: .bottom)

            // Shuffle is hidden for now: ShuffleButton().panelChrome(state, keep: "Shuffle")
            // Apply to All only means something with more than one page.
            if state.pages.count > 1 {
                ActionButton(label: "Apply to All", sf: "square.on.square") { state.applyStyleToAllPages() }
                    .disabled(!state.canApplyToAll)
                    .opacity(state.canApplyToAll ? 1 : 0.5)
                    .panelChrome(state)
            }
        }
    }

    private var canvasPage: some View {
        VStack(spacing: 12) {
            LabeledSlider(label: "Margin", value: $state.canvasMargin, range: -100...100, step: 1, format: "%.0f",
                          resetValue: 0)
            LabeledSlider(label: "Rotation", value: $state.canvasRotation, range: -15...15, step: 0.1, format: "%.1f°",
                          resetValue: 0)
        }
        .swipeNumbersToReset(canReset: state.canvasMargin != 0 || state.canvasRotation != 0) {
            state.canvasMargin = 0
            state.canvasRotation = 0
        }
    }
}

/// The Border page: a full-width size slider, then roomy rows for color,
/// line style and where the line sits.
struct BorderPanel: View {
    @EnvironmentObject var state: CollageState

    var body: some View {
        let off = state.borderThickness <= 0
        VStack(spacing: 14) {
            LabeledSlider(label: "Size", value: $state.borderThickness, range: 0...40, step: 1, format: "%.0f",
                          resetValue: 0)
            row("Color") {
                ColorSwatchButton(color: $state.borderColor,
                                  size: 32,
                                  presetTitle: "Same as Background color",
                                  presetColor: { state.backgroundColor },
                                  depth: 0.55, accessibilityTitle: "Border color")
                Spacer()
            }
            row("Style") {
                BorderStylePicker(large: true)
                Spacer()
            }
            .disabled(off)
            .opacity(off ? 0.4 : 1)
            row("Position") {
                Picker("Position", selection: $state.borderPlacement) {
                    ForEach(BorderPlacement.allCases) { p in Text(p.rawValue).tag(p) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .disabled(off)
            .opacity(off ? 0.4 : 1)
        }
        .swipeNumbersToReset(canReset: state.hasBorderChanges) { state.resetBorder() }
    }

    private func row<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.primary)
                .frame(width: 92, alignment: .leading)
            content()
        }
        .frame(minHeight: 36)
        .panelChrome(state)
    }
}

extension View {
    /// Fades a panel control according to the current focus mode. `keep` is
    /// the control's label; only the matching control stays visible in focus.
    @ViewBuilder
    func panelChrome(_ state: CollageState, keep label: String? = nil) -> some View {
        self
            .opacity(state.chromeVisible(for: label) ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: state.activeAdjustment)
            .animation(.easeInOut(duration: 0.55), value: state.shuffleFocusActive)
    }
}

/// Tappable color circle that opens the system color picker in a sheet
/// from the bottom of the screen; the sheet closes on the first pick.
struct ColorSwatchButton: View {
    @Binding var color: Color
    var supportsOpacity: Bool = true
    var size: CGFloat = 24
    /// Optional quick-preset shown at the top of the picker popover
    /// (e.g. "Same as Background color").
    var presetTitle: String? = nil
    var presetColor: (() -> Color)? = nil
    /// When set, tapping the swatch shows this message instead of the picker
    /// (e.g. while the border color is linked to the background).
    var lockedMessage: String? = nil
    /// Scales how pronounced the recessed (inset) effect is. 1 = full.
    var depth: CGFloat = 1.0
    /// What VoiceOver calls the swatch.
    var accessibilityTitle = "Color"
    @State private var showPicker = false
    @State private var showLockedAlert = false

    /// Global light angle (120°). Derives the inset shading direction:
    /// the rim on the light-source side is shadowed, the far side lit.
    private var lightGeometry: (dark: UnitPoint, lit: UnitPoint, into: CGSize) {
        let rad = Angle(degrees: 120).radians
        let lx = CGFloat(cos(rad))        // light X (math)
        let ly = CGFloat(-sin(rad))       // light Y in screen space (up = -y)
        let dark = UnitPoint(x: 0.5 + lx * 0.5, y: 0.5 + ly * 0.5)   // light-source corner
        let lit  = UnitPoint(x: 0.5 - lx * 0.5, y: 0.5 - ly * 0.5)   // opposite corner
        let into = CGSize(width: -lx * 2, height: -ly * 2)           // shadow cast into the well
        return (dark, lit, into)
    }

    var body: some View {
        #if canImport(UIKit)
        Button {
            if lockedMessage != nil {
                showLockedAlert = true
            } else {
                showPicker = true
            }
        } label: {
            let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            let g = lightGeometry
            ZStack {
                if supportsOpacity {
                    CheckerboardSwatch(cornerRadius: size * 0.3)
                }
                // Recessed color well: an inner shadow (cast from the light
                // side, at the global 120° angle) gives it depth.
                shape.fill(
                    color.shadow(.inner(color: .black.opacity(0.55 * depth),
                                        radius: 2,
                                        x: g.into.width * depth,
                                        y: g.into.height * depth))
                )
                // Edge darkening on the light-source side reinforces the inset
                shape.fill(
                    LinearGradient(stops: [
                        .init(color: .black.opacity(0.28 * depth), location: 0),
                        .init(color: .clear, location: 0.4),
                    ], startPoint: g.dark, endPoint: g.lit)
                )
                // Rim: shaded on the light-source side, lit on the far lip
                shape.strokeBorder(
                    LinearGradient(colors: [.black.opacity(0.35 * depth),
                                            .white.opacity(0.6 * depth)],
                                   startPoint: g.dark, endPoint: g.lit),
                    lineWidth: 1
                )
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityTitle)
        // The system picker rides up from the bottom, over the panel, and
        // closes as soon as a color is picked.
        .sheet(isPresented: $showPicker) {
            VStack(spacing: 0) {
                if let presetTitle, let presetColor {
                    Button {
                        color = presetColor()
                        showPicker = false
                    } label: {
                        Label(presetTitle, systemImage: "circle.lefthalf.filled")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .appButtonBackground(prominent: false)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                }
                UIKitColorPicker(color: $color, supportsAlpha: supportsOpacity) {
                    showPicker = false
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert(lockedMessage ?? "", isPresented: $showLockedAlert) {
            Button("OK", role: .cancel) {}
        }
        #else
        ColorPicker("", selection: $color, supportsOpacity: supportsOpacity)
            .labelsHidden()
            .disabled(lockedMessage != nil)
        #endif
    }
}


/// Small checkerboard shown behind swatches whose color can be transparent.
struct CheckerboardSwatch: View {
    var cornerRadius: CGFloat = 7

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(
                    .image(Image(systemName: "checkerboard.rectangle"), scale: 3)
                ).opacity(0.2)
            )
    }
}

#if canImport(UIKit)
/// Hosts UIColorPickerViewController so it can live inside a popover.
struct UIKitColorPicker: UIViewControllerRepresentable {
    @Binding var color: Color
    let supportsAlpha: Bool
    /// Called on every discrete pick, to commit and dismiss.
    var onCommit: (() -> Void)? = nil

    func makeUIViewController(context: Context) -> UIColorPickerViewController {
        let vc = UIColorPickerViewController()
        vc.supportsAlpha = supportsAlpha
        vc.selectedColor = UIColor(color)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: UIColorPickerViewController, context: Context) {
        // Only push external changes in, otherwise we'd fight the user's
        // in-picker adjustments.
        let current = UIColor(color)
        if !context.coordinator.isPicking, vc.selectedColor != current {
            vc.selectedColor = current
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIColorPickerViewControllerDelegate {
        var parent: UIKitColorPicker
        var isPicking = false

        init(_ parent: UIKitColorPicker) { self.parent = parent }

        func colorPickerViewController(_ viewController: UIColorPickerViewController,
                                       didSelect color: UIColor,
                                       continuously: Bool) {
            isPicking = true
            parent.color = Color(color)
            if !continuously {
                isPicking = false
                // A discrete pick (a tap on a swatch, or the end of a drag)
                // commits and closes the sheet.
                parent.onCommit?()
            }
        }
    }
}
#endif

/// Gear button that opens a popover of toggles choosing which properties
/// the Shuffle button randomizes.
/// Green Shuffle button with an attached gear segment on its left that opens
/// the "What to shuffle" options — the two read as one control.
struct ShuffleButton: View {
    @EnvironmentObject var state: CollageState
    @State private var showOptions = false

    var body: some View {
        HStack(spacing: 0) {
            // Shuffle action segment
            Button { state.shuffleStyle() } label: {
                Label("Shuffle", systemImage: "dice")
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Divider between the two segments
            Rectangle()
                .fill(Color.white.opacity(0.35))
                .frame(width: 1)
                .padding(.vertical, 8)

            // Gear segment (right side)
            Button { showOptions = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showOptions, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("What to shuffle")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        .padding(.bottom, 4)
                    toggle("Columns", \.columns)
                    toggle("Spacing", \.spacing)
                    toggle("Rounding", \.rounding)
                    toggle("Border style", \.borderStyle)
                    toggle("Border thickness", \.borderThickness)
                    toggle("Border position", \.borderPosition)
                    toggle("Color", \.color)
                }
                .padding(.bottom, 8)
                .frame(width: 230)
                // The button tints its content white; reset so popover text
                // is readable in light mode.
                .foregroundColor(.primary)
                .presentationCompactAdaptation(.popover)
            }
        }
        .foregroundColor(.white)
        .frame(height: 38)
        .appButtonBackground(prominent: true)
    }

    private func toggle(_ label: String, _ keyPath: WritableKeyPath<CollageState.ShuffleOptions, Bool>) -> some View {
        Toggle(label, isOn: Binding(
            get: { state.shuffleOptions[keyPath: keyPath] },
            set: { state.shuffleOptions[keyPath: keyPath] = $0 }
        ))
        .toggleStyle(.switch)
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

/// "Spread" button that opens a popover of page-distribution actions.
/// A popover (not a system Menu) keeps the options single-line, wide, and in
/// a fixed top-down order regardless of which way it opens.
struct SpreadMenuButton: View {
    @EnvironmentObject var state: CollageState
    let onOnePerPage: () -> Void
    let onAllOnOne: () -> Void
    var onBurstAll: () -> Void = {}
    @State private var show = false

    var body: some View {
        Button { show = true } label: {
            ToolbarTileLabel(prominent: false, title: "Spread") {
                HStack(spacing: 3) {
                    Image(systemName: "rectangle.split.3x1")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .opacity(0.6)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(state.totalImageCount < 2)
        .opacity(state.totalImageCount < 2 ? 0.5 : 1)
        .help("Requires more than 1 image")
        .popover(isPresented: $show, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                item("Spread across \(state.burstPageCount) page\(state.burstPageCount == 1 ? "" : "s")", "sparkles", onBurstAll)
                item("One image per page", "photo.stack", onOnePerPage)
                item("All images on one page", "rectangle.stack", onAllOnOne)
            }
            .padding(.vertical, 6)
            .frame(width: 270)
            .fixedSize(horizontal: false, vertical: true)
            .presentationCompactAdaptation(.popover)
        }
    }

    private func item(_ title: String, _ sf: String, _ action: @escaping () -> Void) -> some View {
        Button {
            show = false
            // Let the popover dismiss before presenting the confirm alert.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: action)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: sf).frame(width: 22)
                Text(title).lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.subheadline)
            .foregroundColor(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Images toolbar button: icon with a small caption under it.
struct ToolbarTile: View {
    let sf: String
    let title: String
    /// Accent-filled; otherwise a plain outlined tile.
    var prominent = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ToolbarTileLabel(prominent: prominent, title: title) { Image(systemName: sf) }
        }
        .buttonStyle(.plain)
    }
}

/// "Add Page" toolbar tile: a page with a large plus badge (the system
/// doc.badge.plus badge is too small to read at toolbar size).
struct AddPageTile: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ToolbarTileLabel(prominent: true, title: "Add Page") {
                Image(systemName: "doc")
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 13, weight: .bold))
                            // White disc with an accent plus, punched out of
                            // the page outline by an accent ring.
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.accentColor, Color.white)
                            .background(Circle().fill(Color.accentColor).padding(-1.5))
                            .offset(x: 6, y: 4)
                    }
            }
        }
        .buttonStyle(.plain)
    }
}

struct ToolbarTileLabel<Icon: View>: View {
    let prominent: Bool
    let title: String
    @ViewBuilder let icon: Icon

    var body: some View {
        VStack(spacing: 3) {
            icon
                .font(.system(size: 16, weight: .medium))
                .frame(height: 20)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .padding(.horizontal, 4)
        .foregroundColor(prominent ? .white : .primary)
        .appButtonBackground(prominent: prominent)
    }
}

struct ActionButton: View {
    let label: String
    let sf: String
    var isPrimary: Bool = false
    /// When false the button hugs its content instead of expanding to fill.
    var fillWidth: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if label.isEmpty {
                    Image(systemName: sf)
                } else {
                    Label(label, systemImage: sf)
                }
            }
            .font(.footnote.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, fillWidth ? 8 : 12)
            .frame(maxWidth: fillWidth ? .infinity : nil)
            .padding(.vertical, 10)
            .foregroundColor(isPrimary ? .white : .primary)
            .appButtonBackground(prominent: isPrimary)
        }
        .buttonStyle(.plain)
    }
}

struct CustomSizeRow: View {
    @EnvironmentObject var state: CollageState

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                TextField("W", text: $state.customWidth)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    #if canImport(UIKit)
                    .keyboardType(.numberPad)
                    #endif
                Text("×").foregroundColor(.secondary)
                TextField("H", text: $state.customHeight)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    #if canImport(UIKit)
                    .keyboardType(.numberPad)
                    #endif
                // Unit toggle
                Picker("", selection: $state.customUnit) {
                    ForEach(CustomUnit.allCases) { u in
                        Text(u.rawValue).tag(u)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 80)
            }
            Button("Apply") { state.applyCustomSize() }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Page groups (shared by sidebar and bottom panel)

/// One rounded group row per page, holding that page's thumbnails.
/// Tapping a row makes its page current; the trash removes the page.
struct PageGroupsView: View {
    @EnvironmentObject var state: CollageState
    @Environment(\.colorScheme) private var colorScheme
    @State private var dropTargetPage: Int? = nil
    @State private var rowFrames: [Int: CGRect] = [:]
    // Custom page reordering (no system drag badge)
    @State private var dragPageIndex: Int? = nil
    @State private var dragPageLocation: CGPoint = .zero
    // Moving a photo (to another spot or page): picked up as soon as the
    // finger moves, in any direction.
    @State private var dragThumb: CollageImage? = nil
    @State private var dragThumbLocation: CGPoint = .zero
    /// Set once a touch on a thumbnail has moved far enough to pick it up.
    @State private var thumbDragIsMove: Bool? = nil
    /// Where each thumbnail sits (for dropping one photo onto another to
    /// swap them), and the one under the finger.
    @State private var thumbFrames: [UUID: CGRect] = [:]
    @State private var dropTargetThumb: UUID? = nil

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(state.pages.enumerated()), id: \.element.id) { pi, page in
                pageRow(pi: pi, page: page)
            }
        }
        .coordinateSpace(name: "pageGroups")
        // The photo being moved follows the finger.
        .overlay {
            if let img = dragThumb {
                thumbDragPreview(img.thumb)
                    .scaleEffect(0.85)
                    .position(dragThumbLocation)
                    .allowsHitTesting(false)
            }
        }
        // Floating "rearrange" chip while dragging a page grip
        .overlay {
            if dragPageIndex != nil {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor))
                    .position(dragPageLocation)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Immediate drag gesture for the page grip: reorders pages by swapping
    /// with the row under the finger. Uses a custom gesture (not .draggable)
    /// so no system copy (+) badge appears.
    private func pageDragGesture(pageIndex: Int) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named("pageGroups"))
            .onChanged { value in
                if dragPageIndex == nil { dragPageIndex = pageIndex }
                dragPageLocation = value.location
                dropTargetPage = rowFrames.first { $0.value.contains(value.location) }?.key
            }
            .onEnded { value in
                defer {
                    dragPageIndex = nil
                    dropTargetPage = nil
                }
                guard let from = dragPageIndex,
                      let target = rowFrames.first(where: { $0.value.contains(value.location) })?.key,
                      from != target else { return }
                withAnimation { state.swapPages(from, target) }
            }
    }

    /// Picks up a thumbnail as soon as it's dragged, in any direction (the
    /// rows wrap, so there's no sideways scrolling to tell apart). Dropped
    /// on another photo of its page, the two swap places in the collage;
    /// dropped on another page row, it moves there.
    private func thumbDragGesture(_ img: CollageImage) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named("pageGroups"))
            .onChanged { value in
                if thumbDragIsMove == nil {
                    thumbDragIsMove = true
                    dragThumb = img
                    state.isMovingThumb = true
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                }
                dragThumbLocation = value.location
                let home = state.pageIndex(containing: img.id)
                let swapWith = thumbUnder(value.location, samePageAs: img)
                if swapWith != dropTargetThumb {
                    dropTargetThumb = swapWith
                    #if canImport(UIKit)
                    if swapWith != nil { UISelectionFeedbackGenerator().selectionChanged() }
                    #endif
                }
                let over = rowFrames.first { $0.value.contains(value.location) }?.key
                dropTargetPage = over == home ? nil : over
            }
            .onEnded { value in
                defer {
                    dragThumb = nil
                    thumbDragIsMove = nil
                    dropTargetPage = nil
                    dropTargetThumb = nil
                    state.isMovingThumb = false
                }
                guard thumbDragIsMove == true else { return }
                // Onto another photo of the same page: swap the two.
                if let other = thumbUnder(value.location, samePageAs: img),
                   let pi = state.pageIndex(containing: img.id) {
                    withAnimation(.easeInOut(duration: 0.25)) { state.swapImages(onPage: pi, img.id, other) }
                    return
                }
                guard let target = rowFrames.first(where: { $0.value.contains(value.location) })?.key,
                      state.pageIndex(containing: img.id) != target,
                      state.pages.indices.contains(target),
                      state.pages[target].images.count < CollageState.maxImagesPerPage else { return }
                withAnimation { state.moveImage(id: img.id, toPage: target) }
            }
    }

    /// Another thumbnail of `img`'s page under `point`, if any.
    private func thumbUnder(_ point: CGPoint, samePageAs img: CollageImage) -> UUID? {
        guard let pi = state.pageIndex(containing: img.id) else { return nil }
        return state.pages[pi].images.first { $0.id != img.id && thumbFrames[$0.id]?.contains(point) == true }?.id
    }

    /// A page's photos in collage order (the order swaps change).
    private func orderedImages(_ page: CollagePage) -> [CollageImage] {
        let byId = Dictionary(page.images.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let ordered = page.order.compactMap { byId[$0] }
        return ordered + page.images.filter { !page.order.contains($0.id) }
    }

    /// Enlarged preview shown while a thumbnail is being dragged.
    @ViewBuilder
    private func thumbDragPreview(_ image: PlatformImage) -> some View {
        #if canImport(UIKit)
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: 84, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.4), radius: 10, y: 5)
        #else
        Image(nsImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: 84, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.4), radius: 10, y: 5)
        #endif
    }

    /// Light mode: a soft gray well (accent-tinted for the current page).
    /// Dark mode: a deep, near-black well so the rows stand out from the
    /// dark glass, with the accent tint on top for the current page.
    private func rowBackground(isCurrent: Bool, isDropTarget: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12)
        let dark = colorScheme == .dark
        let tint: Double = isDropTarget ? (dark ? 0.35 : 0.25) : isCurrent ? (dark ? 0.22 : 0.12) : 0
        return shape
            .fill(dark ? Color.black.opacity(0.55)
                       : (tint > 0 ? Color.clear : Color(.systemFill).opacity(0.5)))
            .overlay(shape.fill(Color.accentColor.opacity(tint)))
            .overlay(shape.strokeBorder(Color.white.opacity(dark ? 0.08 : 0), lineWidth: 1))
    }

    @ViewBuilder
    private func pageRow(pi: Int, page: CollagePage) -> some View {
        let isCurrent = pi == state.currentPageIndex

        HStack(spacing: 8) {
            // Full-height grip rail: drag it onto another row to swap
            // page positions
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.7))
                .frame(width: 24)
                .frame(maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemFill).opacity(0.7))
                )
                .opacity(dragPageIndex == pi ? 0.4 : 1)
                .contentShape(Rectangle())
                .gesture(pageDragGesture(pageIndex: pi))

            // Add photos straight into this page.
            PageAddPhotosButton(pageIndex: pi)

            if page.images.isEmpty {
                Text("No images")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
            } else {
                // Wraps onto more lines instead of scrolling sideways, so a
                // drag in any direction picks a photo up.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 58, maximum: 58), spacing: 6)],
                          alignment: .leading, spacing: 6) {
                    ForEach(orderedImages(page)) { img in
                        ImageThumb(img: img)
                            // Drag onto another photo to swap them, or
                            // onto another page row to move it there.
                            .opacity(dragThumb?.id == img.id ? 0.3 : 1)
                            .overlay {
                                if dropTargetThumb == img.id {
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(Color.accentColor, lineWidth: 3)
                                }
                            }
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("pageGroups")) } action: {
                                thumbFrames[img.id] = $0
                            }
                            .simultaneousGesture(thumbDragGesture(img))
                    }
                }
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if state.pages.count > 1 {
                Button {
                    state.deletePage(at: pi)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(width: 20)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(8)
        .background(rowBackground(isCurrent: isCurrent, isDropTarget: dropTargetPage == pi))
        .contentShape(Rectangle())
        .onTapGesture {
            state.goToPage(pi)
        }
        // Accept a thumbnail dropped from another page row
        .dropDestination(for: String.self) { items, _ in
            guard let idString = items.first, let id = UUID(uuidString: idString),
                  state.pageIndex(containing: id) != pi,
                  state.pages.indices.contains(pi),
                  state.pages[pi].images.count < CollageState.maxImagesPerPage else { return false }
            withAnimation { state.moveImage(id: id, toPage: pi) }
            return true
        } isTargeted: { over in
            dropTargetPage = over ? pi : (dropTargetPage == pi ? nil : dropTargetPage)
        }
        // Track the row frame for instant thumbnail drops
        .background(
            GeometryReader { g in
                Color.clear
                    .onAppear { rowFrames[pi] = g.frame(in: .named("pageGroups")) }
                    .onChange(of: g.frame(in: .named("pageGroups"))) { _, f in
                        rowFrames[pi] = f
                    }
            }
        )
    }
}

// MARK: - Per-page "add photos" tile

/// First tile of a page row: picks photos into that page (spilling onto new
/// pages once it's full) and shows it.
struct PageAddPhotosButton: View {
    @EnvironmentObject var state: CollageState
    let pageIndex: Int
    var size: CGFloat = 58
    @State private var items: [PhotosPickerItem] = []

    var body: some View {
        PhotosPicker(selection: $items, maxSelectionCount: 30, matching: .images) {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: size, height: size)
                .appButtonBackground(prominent: true)
                .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add photos to page \(pageIndex + 1)")
        .onChange(of: items) { _, picked in load(picked) }
    }

    private func load(_ picked: [PhotosPickerItem]) {
        guard !picked.isEmpty else { return }
        let target = pageIndex
        state.isBusy = true
        state.isLoading = true
        Task {
            var loaded: [PlatformImage] = []
            for item in picked {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = PlatformImage(data: data) {
                    loaded.append(img)
                }
            }
            // Generate proxies/thumbnails off the main thread
            let images = loaded
            let prepared = await Task.detached(priority: .userInitiated) {
                images.map { CollageImage(image: $0) }
            }.value
            await MainActor.run {
                state.addPreparedImages(prepared, toPage: target)
                state.goToPage(target)
                items = []
                state.isBusy = false
                state.isLoading = false
            }
        }
    }
}

// MARK: - Image thumbnail (shared by sidebar and bottom panel)

struct ImageThumb: View {
    @EnvironmentObject var state: CollageState
    let img: CollageImage
    var size: CGFloat = 58

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Thumbnails are only for rearranging across pages — no context
            // menu here (Replace / Delete live on the canvas boxes).
            thumbImage

            Button { state.removeImage(id: img.id) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 18, height: 18)
                    .background(Color.black.opacity(0.7))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .offset(x: -3, y: 3)
        }
    }

    @ViewBuilder
    private var thumbImage: some View {
        if img.isPlaceholder {
            // The placeholder's pixels are transparent, so mark it with a
            // dashed empty-slot glyph instead of an invisible square.
            RoundedRectangle(cornerRadius: 6)
                .fill(ColorManager.systemFill.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.secondary.opacity(0.6),
                                      style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                )
                .overlay(
                    Image(systemName: "rectangle.dashed")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.secondary)
                )
                .frame(width: size, height: size)
        } else {
            #if canImport(UIKit)
            Image(uiImage: img.thumb)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            #else
            Image(nsImage: img.thumb)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            #endif
        }
    }
}

// MARK: - Export sheet

struct ExportSheetView: View {
    @EnvironmentObject var state: CollageState
    @Environment(\.dismiss) var dismiss

    var body: some View {
        #if canImport(UIKit)
        if !state.exportedFiles.isEmpty {
            ActivityView(items: state.exportedFiles) { dismiss() }
        }
        #else
        VStack(spacing: 16) {
            Text("Export PNG").font(.headline)
            Text(state.exportedFiles.count == 1
                 ? "1 page ready"
                 : "\(state.exportedFiles.count) pages ready")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Button("Save to Desktop") {
                let desktop = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Desktop")
                for url in state.exportedFiles {
                    let dest = desktop.appendingPathComponent("collage_\(url.lastPathComponent)")
                    try? FileManager.default.removeItem(at: dest)
                    try? FileManager.default.copyItem(at: url, to: dest)
                }
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            Button("Cancel", role: .cancel) { dismiss() }
        }
        .padding(24)
        .frame(width: 400)
        #endif
    }
}

#if canImport(UIKit)
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        vc.completionWithItemsHandler = { _, _, _, _ in onDismiss() }
        return vc
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

// MARK: - Color(hex:) helper

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
