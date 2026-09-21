import SwiftUI
#if canImport(PhotosUI)
import PhotosUI
#endif

struct SidebarView: View {
    @EnvironmentObject var state: CollageState
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showingCustom = false
    @State private var showOneOnOneConfirm = false
    @State private var showBurstConfirm = false
    @State private var showBurstAllConfirm = false
    @State private var showAllOnOneConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                logo
                if let textId = state.textEditTargetId {
                    SidebarSection(title: "Text") {
                        TextEditPanel(imageId: textId)
                    }
                }
                imagesSection
                ratioSection
                layoutSection
                borderSection
                framesSection
                overlaySection
                effectsSection
            }
        }
        .onChange(of: photoItems) { _, newItems in
            loadPhotos(newItems)
        }
    }

    // MARK: - Logo

    var logo: some View {
        HStack(spacing: 10) {
            Image("DasKolazLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 80)
                .shimmering(state.isBusy)
            Spacer()
            // Export / share the collage as PNG
            Button {
                if state.pages.count > 1 {
                    state.showExportOptions = true
                } else {
                    Task { await state.exportPages(allPages: false) }
                }
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
                PhotosPicker(selection: $photoItems, maxSelectionCount: 30, matching: .images) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 17, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundColor(.white)
                        .background(Color.accentColor)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)

                // Adds a transparent placeholder — an intentional empty slot.
                Button { state.addEmptyImage() } label: {
                    Image(systemName: "rectangle.dashed.badge.record")
                        .font(.system(size: 17, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundColor(.white)
                        .background(Color.accentColor)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)

                // Adds an editable text box rendered as an image.
                Button { state.addTextImage() } label: {
                    Image(systemName: "character.textbox")
                        .font(.system(size: 17, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundColor(.white)
                        .background(Color.accentColor)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)

                ActionButton(label: "", sf: "doc.badge.plus") { state.addPage() }
                    .disabled(state.pages.count >= CollageState.maxPages)
                    .opacity(state.pages.count >= CollageState.maxPages ? 0.5 : 1)

                SpreadMenuButton(
                    onBurst: { showBurstConfirm = true },
                    onOnePerPage: { showOneOnOneConfirm = true },
                    onAllOnOne: { showAllOnOneConfirm = true },
                    onBurstAll: { showBurstAllConfirm = true })

                ActionButton(label: "", sf: "trash", fillWidth: false) { state.clear() }
            }
            .alert("Burst!", isPresented: $showBurstAllConfirm) {
                Button("Proceed") { state.burstBalanced() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will spread all \(state.totalImageCount) images across \(state.burstPageCount) balanced page\(state.burstPageCount == 1 ? "" : "s"), do you want to proceed?")
            }
            .alert("One image per page", isPresented: $showOneOnOneConfirm) {
                Button("Proceed") { state.distributeOneImagePerPage() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will add 1 image per 1 page, do you want to proceed?")
            }
            .alert("Spread images across pages", isPresented: $showBurstConfirm) {
                Button("Proceed") { state.burstAcrossPages() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will distribute all images evenly across the \(state.pages.count) page\(state.pages.count == 1 ? "" : "s"), do you want to proceed?")
            }
            .alert("All images on one page", isPresented: $showAllOnOneConfirm) {
                Button("Proceed") { state.mergeAllOntoOnePage() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will put all images on a single page and delete the other pages, do you want to proceed?")
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
            LabeledSlider(label: "Columns", value: Binding(
                get: { Double(min(state.numCols, state.maxSelectableCols)) },
                set: { v in state.numCols = Int(v); state.rebuildLayout(resetGrows: true) }
            ), range: 1...Double(state.maxSelectableCols), step: 1, format: "%.0f", resetValue: 2)
                .disabled(state.maxSelectableCols <= 1)
                .opacity(state.maxSelectableCols <= 1 ? 0.4 : 1)
            
            /*
            struct LabeledSlider: View {
                let label: String
                @Binding var value: Double
                let range: ClosedRange<Double>
                let step: Double
                let format: String
             */

            LabeledSlider(label: "Spacing", value: $state.gap, range: 0...40, step: 1, format: "%.0f",
                          resetValue: 10, swatchColor: $state.backgroundColor)

            LabeledSlider(label: "Rounding", value: $state.cornerRadius, range: 0...100, step: 1, format: "%.0f",
                          resetValue: 20)
                // The chain sits in this row's empty swatch slot, visually
                // connecting the Background and Border color circles
                .overlay(alignment: .trailing) {
                    ColorLinkToggle().panelChrome(state)
                }

            BorderStyleRow()

            BorderPlacementRow()

            HStack(spacing: 8) {
                ShuffleButton()
                ActionButton(label: "Apply to All", sf: "square.on.square") { state.applyStyleToAllPages() }
                    .disabled(!state.canApplyToAll || state.pages.count <= 1)
                    .opacity(state.pages.count <= 1 ? 0 : (state.canApplyToAll ? 1 : 0.5))
                    .allowsHitTesting(state.pages.count > 1)
                ActionButton(label: "Reset", sf: "arrow.counterclockwise", fillWidth: false) { state.resetStyle() }
            }
        }
    }

    // MARK: - Canvas (margin + rotation)

    var borderSection: some View {
        SidebarSection(title: "Canvas") {
            LabeledSlider(label: "Margin", value: $state.canvasMargin, range: -100...100, step: 1, format: "%.0f",
                          resetValue: 0)
            LabeledSlider(label: "Rotation", value: $state.canvasRotation, range: -60...60, step: 1, format: "%.0f°",
                          resetValue: 0)
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

    // MARK: - Effects (fade, halation, glow, B&W, …)

    var effectsSection: some View {
        SidebarSection(title: "Effects") {
            EffectsPanel()
        }
    }

    // MARK: - Load photos

    func loadPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        state.isBusy = true
        state.isLoading = true
        Task {
            var loaded: [PlatformImage] = []
            for item in items {
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
                state.addPreparedImages(prepared)
                photoItems = []
                state.isBusy = false
                state.isLoading = false
            }
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
            // White text on a dark fill so it stays readable over the very
            // transparent glass panel.
            .foregroundColor(.white)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(isActive ? Color.accentColor : Color.black.opacity(0.55))
            )
        }
        .buttonStyle(.plain)
    }
}

/// Embossed metallic slider knob: brushed-metal ball lit from the top left,
/// with a bright rim highlight and a drop shadow that lifts it off the track.
struct EmbossedKnobThumb: View {
    var size: CGFloat

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [Color(white: 0.99), Color(white: 0.87), Color(white: 0.66)],
                                 center: UnitPoint(x: 0.35, y: 0.28),
                                 startRadius: 1,
                                 endRadius: size * 0.95))
            .overlay(
                Circle().strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(0.95), Color(white: 0.45)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1)
            )
            .frame(width: size, height: size)
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

    @Environment(\.colorScheme) private var colorScheme
    @State private var isDragging = false

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
                Capsule()
                    .fill(
                        LinearGradient(colors: isDark
                                       ? [Color(white: 0.13), Color(white: 0.30)]
                                       : [Color(white: 0.70), Color(white: 0.94)],
                                       startPoint: .top, endPoint: .bottom)
                        .shadow(.inner(color: .black.opacity(isDark ? 0.7 : 0.45),
                                       radius: 2, y: 1.5))
                    )
                    .overlay(
                        Capsule().strokeBorder(
                            LinearGradient(colors: isDark
                                           ? [Color.black.opacity(0.8), Color.white.opacity(0.15)]
                                           : [Color(white: 0.45), Color.white.opacity(0.95)],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: 1)
                    )
                    .frame(height: 22)
                    // Light catching the bottom lip of the recess
                    .shadow(color: .white.opacity(isDark ? 0.08 : 0.8), radius: 0.5, y: 1)

                // Recessed inner track — a subtle gray groove (not hard black)
                // with a soft inner shadow for a gentle 3D dip
                Capsule()
                    .fill(
                        LinearGradient(colors: isDark
                                       ? [Color(white: 0.22), Color(white: 0.32)]
                                       : [Color(white: 0.52), Color(white: 0.66)],
                                       startPoint: .top, endPoint: .bottom)
                        .shadow(.inner(color: .black.opacity(isDark ? 0.45 : 0.30),
                                       radius: 1, y: 1))
                    )
                    .frame(height: 14)
                    .padding(.horizontal, 4)

                // Value fill inside the recess
                Capsule()
                    .fill(LinearGradient(colors: [Color.accentColor.opacity(0.55), Color.accentColor],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(thumbX - 4, 14), height: 14)
                    .padding(.leading, 4)

                EmbossedKnobThumb(size: thumbSize)
                    .shadow(color: .black.opacity(0.4), radius: isDragging ? 5 : 2.5, y: 2)
                    .offset(x: thumbX - thumbSize / 2)
            }
            .frame(maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            // Drag starts instantly (no double-tap gesture competing for the
            // touch — double-tap-to-reset lives on the value number instead).
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if !isDragging { onEditingChanged?(true) }
                        isDragging = true
                        let f = min(max((g.location.x - thumbBase / 2) / usable, 0), 1)
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
                    .onEnded { _ in
                        isDragging = false
                        onEditingChanged?(false)
                    }
            )
        }
        .frame(height: 32)
        .animation(.easeOut(duration: 0.12), value: isDragging)
    }
}

struct LabeledSlider: View {
    @EnvironmentObject var state: CollageState
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: String
    /// Double-tap reset value, forwarded to the slider.
    var resetValue: Double? = nil
    var labelWidth: CGFloat = 76
    /// Optional color bound to a leading swatch circle. Rows without one show
    /// an empty slot of the same size so all labels stay aligned.
    var swatchColor: Binding<Color>? = nil

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.primary)
                .frame(width: labelWidth, alignment: .leading)
            ModernSlider(value: $value, range: range, step: step,
                         onEditingChanged: { editing in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                state.activeAdjustment = editing ? label : nil
                            }
                         },
                         resetValue: resetValue)
            Text(String(format: format, value))
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(.accentColor)
                .lineLimit(1)
                .fixedSize()
                .frame(width: 44, alignment: .center)
                // Double-tapping the value also resets to default
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    value = min(max(resetValue ?? 0, range.lowerBound), range.upperBound)
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                }
            if let swatchColor {
                ColorSwatchButton(color: swatchColor, depth: 0.55)
                    // Pure minimal in focus mode: only label + slider + value.
                    .panelChrome(state)
            } else {
                Color.clear.frame(width: 24, height: 24)
            }
        }
        // A small "private" glass panel appears behind this row while it's the
        // one being adjusted, so its label stays readable over the canvas.
        .background { focusGlass(active: state.activeAdjustment == label) }
        // Focus mode: fade this row out when another slider is active or the
        // panel is in shuffle focus.
        .opacity(state.chromeVisible(for: label) ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: state.activeAdjustment)    }
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
    @State private var showChooser = false

    var body: some View {
        Button {
            showChooser = true
        } label: {
            HStack(spacing: 4) {
                BorderPatternPreview(style: state.borderStyle)
                    .frame(width: 50, height: 16)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemFill)))
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

/// Chain toggle rendered between the Background swatch (Spacing row) and the
/// Border swatch (Border row). When linked, the border color follows the
/// background color; tapping toggles the link.
struct ColorLinkToggle: View {
    @EnvironmentObject var state: CollageState

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                state.linkBorderToBackground.toggle()
            }
        } label: {
            VStack(spacing: 2) {
                strand
                Image(systemName: "link")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(state.linkBorderToBackground
                                     ? .accentColor
                                     : .secondary.opacity(0.45))
                strand
            }
            .frame(width: 24)
            // Reach out of the row toward the color circles above and below
            .padding(.vertical, -14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Link border color to background color")
    }

    private var strand: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(state.linkBorderToBackground
                  ? Color.accentColor
                  : Color.secondary.opacity(0.25))
            .frame(width: 2, height: 14)
    }
}

/// Border row: pattern chooser first, then the thickness slider, so the
/// value number docks to the right edge like the other slider rows.
struct BorderStyleRow: View {
    @EnvironmentObject var state: CollageState
    var range: ClosedRange<Double> = 0...40

    var body: some View {
        HStack(spacing: 8) {
            Text("Border")
                .font(.subheadline)
                .foregroundColor(.primary)
                .frame(width: 76, alignment: .leading)
            BorderStylePicker()
                .fixedSize()
                .disabled(state.borderThickness <= 0)
                .opacity(state.activeAdjustment != nil ? 0 : (state.borderThickness <= 0 ? 0.4 : 1))
            ModernSlider(value: $state.borderThickness, range: range, step: 1,
                         onEditingChanged: { editing in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                state.activeAdjustment = editing ? "Border" : nil
                            }
                         },
                         resetValue: 0)
            Text(String(format: "%.0f", state.borderThickness))
                .font(.system(size: 14, design: .monospaced))
                .foregroundColor(.accentColor)
                .lineLimit(1)
                .fixedSize()
                .frame(width: 44, alignment: .center)
                // Double-tapping the value resets border thickness to zero.
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    state.borderThickness = 0
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                }
            ColorSwatchButton(color: $state.borderColor,
                              presetTitle: "Same as Background color",
                              presetColor: { state.backgroundColor },
                              lockedMessage: state.linkBorderToBackground
                                  ? "Unlink colors to change the border color"
                                  : nil,
                              depth: 0.55)
                .panelChrome(state)
        }
        .background { focusGlass(active: state.activeAdjustment == "Border") }
        .opacity(state.chromeVisible(for: "Border") ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: state.activeAdjustment)    }
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

/// Segmented chooser for where the border line sits relative to the
/// image box edge: inside it, centered on it, or outside it.
struct BorderPlacementRow: View {
    @EnvironmentObject var state: CollageState

    var body: some View {
        let disabled = state.borderThickness <= 0
        HStack(spacing: 8) {
            Text("Position")
                .font(.subheadline)
                .foregroundColor(.primary)
                .opacity(disabled ? 0.35 : 1)
                .frame(width: 76, alignment: .leading)
            Picker("", selection: $state.borderPlacement) {
                ForEach(BorderPlacement.allCases) { p in
                    Text(p.rawValue).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(disabled)
            .opacity(disabled ? 0.4 : 1)
            // Match the sliders' value + swatch trailing block width
            Color.clear.frame(width: 44 + 8 + 24, height: 24)
        }
        .panelChrome(state)
    }
}

/// Tappable color circle that opens the system color picker in a popover:
/// no background dimming, and the collage stays visible while the color
/// updates live.
/// A compact grid of large, curated color blocks for quick selection,
/// shown above the full color picker.
struct PalettePickerGrid: View {
    @Binding var color: Color

    private let palette: [Color] = [
        .white,
        Color(hex: "F5EFE6"),   // cream
        Color(hex: "D9D9D9"),   // light gray
        Color(hex: "9CAF88"),   // sage
        Color(hex: "F3C8AB"),   // peach
        Color(hex: "C96F4A"),   // terracotta
        Color(hex: "D9A441"),   // mustard
        Color(hex: "7C9CB0"),   // dusty blue
        Color(hex: "2E3A59"),   // navy
        Color(hex: "E8B4B8"),   // blush
        Color(hex: "3A3A3A"),   // charcoal
        .black,
    ]

    private let columns = [GridItem(.adaptive(minimum: 50), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(palette.indices, id: \.self) { i in
                let c = palette[i]
                Button {
                    color = c
                } label: {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(c)
                        .frame(height: 50)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                        )
                        .overlay {
                            if isSelected(c) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.5), radius: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Rough equality so the current color shows a checkmark.
    private func isSelected(_ c: Color) -> Bool {
        #if canImport(UIKit)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        UIColor(c).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        UIColor(color).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return abs(r1 - r2) < 0.02 && abs(g1 - g2) < 0.02 && abs(b1 - b2) < 0.02
        #else
        return false
        #endif
    }
}

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
        .popover(isPresented: $showPicker, arrowEdge: .bottom) {
            VStack(spacing: 12) {
                if let presetTitle, let presetColor {
                    Button {
                        color = presetColor()
                        showPicker = false
                    } label: {
                        Label(presetTitle, systemImage: "circle.lefthalf.filled")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color(.systemFill)))
                    }
                    .buttonStyle(.plain)
                }
                // Quick big-block palette — a few curated colors.
                PalettePickerGrid(color: $color)
                UIKitColorPicker(color: $color, supportsAlpha: supportsOpacity) {
                    // Double-selecting the same color commits and closes
                    showPicker = false
                }
            }
            // Even padding around the whole dialog on every side.
            .padding(14)
            .frame(width: 300, height: presetTitle == nil ? 470 : 510)
            .presentationCompactAdaptation(.popover)
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
    /// Called when the user re-selects the currently selected color (a
    /// double-tap on the same swatch), to commit and dismiss.
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
        private var lastColor: UIColor?
        private var lastSelectTime: Date?

        init(_ parent: UIKitColorPicker) { self.parent = parent }

        func colorPickerViewController(_ viewController: UIColorPickerViewController,
                                       didSelect color: UIColor,
                                       continuously: Bool) {
            isPicking = true
            parent.color = Color(color)
            if !continuously {
                isPicking = false
                // A discrete re-selection of the same color within a short
                // window = double-tap → commit and close.
                let now = Date()
                if let last = lastColor, last == color,
                   let t = lastSelectTime, now.timeIntervalSince(t) < 0.5 {
                    lastColor = nil
                    lastSelectTime = nil
                    parent.onCommit?()
                } else {
                    lastColor = color
                    lastSelectTime = now
                }
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
        .background(Color.accentColor)
        .cornerRadius(10)
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
    let onBurst: () -> Void
    let onOnePerPage: () -> Void
    let onAllOnOne: () -> Void
    var onBurstAll: () -> Void = {}
    @State private var show = false

    var body: some View {
        Button { show = true } label: {
            HStack(spacing: 4) {
                Image(systemName: "rectangle.split.3x1")
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .opacity(0.6)
            }
            .font(.footnote.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundColor(.primary)
            .background(Color(.systemFill))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .disabled(state.totalImageCount < 2)
        .opacity(state.totalImageCount < 2 ? 0.5 : 1)
        .help("Requires more than 1 image")
        .popover(isPresented: $show, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                item("Burst! (\(state.burstPageCount) page\(state.burstPageCount == 1 ? "" : "s"))", "sparkles", onBurstAll)
                item("Spread across open pages", "square.grid.3x3", onBurst)
                item("1 image per page", "doc.on.doc", onOnePerPage)
                item("All images on 1 page", "rectangle.stack", onAllOnOne)
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
            .background(isPrimary ? Color.accentColor : Color(.systemFill))
            .cornerRadius(10)
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
    @State private var dropTargetPage: Int? = nil
    @State private var rowFrames: [Int: CGRect] = [:]
    // Custom page reordering (no system drag badge)
    @State private var dragPageIndex: Int? = nil
    @State private var dragPageLocation: CGPoint = .zero

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(state.pages.enumerated()), id: \.element.id) { pi, page in
                pageRow(pi: pi, page: page)
            }
        }
        .coordinateSpace(name: "pageGroups")
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

            if page.images.isEmpty {
                Text("No images")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(page.images) { img in
                            ImageThumb(img: img)
                                // System drag: a swipe scrolls the strip, a
                                // press-and-hold lifts the thumb (shown larger)
                                // to drop on another page row.
                                .draggable(img.id.uuidString) {
                                    thumbDragPreview(img.thumb)
                                }
                        }
                    }
                    .padding(.vertical, 2)
                }
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
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(dropTargetPage == pi
                      ? Color.accentColor.opacity(0.25)
                      : isCurrent ? Color.accentColor.opacity(0.12) : Color(.systemFill).opacity(0.5))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            state.currentPageIndex = pi
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
