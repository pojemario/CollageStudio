import SwiftUI

/// The parts of a page's settings that can be copied to other pages.
enum PageLookPart: String, CaseIterable, Identifiable {
    case layout = "Layout"
    case background = "Background"
    case border = "Border"
    case canvas = "Margin & Rotation"
    case frame = "Frame"
    case overlays = "Overlays"
    case edits = "Edits"
    case filter = "Filter"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .layout: return "square.grid.2x2"
        case .background: return "paintbrush"
        case .border: return "square.dashed"
        case .canvas: return "rotate.right"
        case .frame: return "photo.artframe"
        case .overlays: return "sparkles"
        case .edits: return "slider.horizontal.3"
        case .filter: return "camera.filters"
        }
    }
}

/// A page's settings on the clipboard, from the page menu's Copy.
struct CopiedPageLook {
    let pageId: UUID
    let style: PageStyle
    let look: PageLook
}

extension CollageState {
    /// Puts the current page's settings on the clipboard.
    func copyPageLook() {
        copiedPageLook = CopiedPageLook(pageId: currentPage.id, style: currentPage.style, look: currentPage.look)
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    /// Page number (1-based) the clipboard came from, if that page is still here.
    var copiedPageNumber: Int? {
        guard let id = copiedPageLook?.pageId else { return nil }
        return pages.firstIndex { $0.id == id }.map { $0 + 1 }
    }

    /// Copies the chosen parts of the clipboard onto the given pages.
    func pastePageLook(_ parts: Set<PageLookPart>, to targets: Set<Int>) {
        guard let clip = copiedPageLook, !parts.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            for i in targets where pages.indices.contains(i) {
                var page = pages[i]
                let src = clip.style, look = clip.look
                if parts.contains(.layout) {
                    let cols = max(1, min(src.numCols, max(1, min(6, page.images.count))))
                    let relayout = cols != page.style.numCols || src.isRows != page.style.isRows
                    page.style.numCols = cols
                    page.style.isRows = src.isRows
                    page.style.gap = src.gap
                    page.style.cornerRadius = src.cornerRadius
                    if relayout {
                        page.layout.resetGrows()
                        page.layout.rebuild(images: page.images, order: page.order, numCols: cols)
                    }
                }
                if parts.contains(.background) {
                    page.style.backgroundColor = src.backgroundColor
                    page.style.backgroundKind = src.backgroundKind
                    page.style.backgroundColor2 = src.backgroundColor2
                }
                if parts.contains(.border) {
                    page.style.borderColor = src.borderColor
                    page.style.borderThickness = src.borderThickness
                    page.style.borderStyle = src.borderStyle
                    page.style.borderPlacement = src.borderPlacement
                    page.style.linkBorderToBackground = src.linkBorderToBackground
                }
                if parts.contains(.canvas) {
                    page.look.canvasMargin = look.canvasMargin
                    page.look.canvasRotation = look.canvasRotation
                }
                if parts.contains(.frame) { page.look.canvasFrame = look.canvasFrame }
                if parts.contains(.overlays) { page.look.overlayLayers = look.overlayLayers }
                if parts.contains(.edits) {
                    page.look.effects = look.effects
                    page.look.hsl = look.hsl
                    page.look.calibration = look.calibration
                }
                if parts.contains(.filter) {
                    page.look.colorFilter = look.colorFilter
                    page.look.filterStrength = look.filterStrength
                }
                pages[i] = page
            }
        }
        if !overlayLayers.contains(where: { $0.id == selectedOverlayId }) {
            selectedOverlayId = overlayLayers.last?.id
        }
        dropGradesIfIdentity()
        refreshTrackedGeometry(after: 0.45)
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}

/// The page menu's Paste: which parts of the copied page's settings go
/// onto which pages.
struct PastePageLookView: View {
    @EnvironmentObject var state: CollageState
    @Environment(\.dismiss) private var dismiss
    @State private var parts: Set<PageLookPart> = PastePageLookView.savedParts
    @State private var targets: Set<Int> = []
    /// Opened as "Copy to Other Pages": every page but the source starts selected.
    var allOtherPages = false

    var body: some View {
        NavigationStack {
            Form {
                if let clip = state.copiedPageLook {
                    Section {
                        pageGrid
                    } header: {
                        HStack {
                            Text("Paste To")
                            Spacer()
                            Button(targets == otherPages ? "None" : "All") {
                                targets = targets == otherPages ? [] : otherPages
                            }
                            .font(.footnote.weight(.semibold))
                            .textCase(nil)
                        }
                    }
                    Section {
                        ForEach(PageLookPart.allCases) { part in
                            partRow(part, detail: detail(part, clip))
                        }
                    } header: {
                        HStack {
                            Text(state.copiedPageNumber.map { "From Page \($0)" } ?? "Copied Settings")
                            Spacer()
                            Button(parts.count == PageLookPart.allCases.count ? "None" : "All") {
                                parts = parts.count == PageLookPart.allCases.count ? [] : Set(PageLookPart.allCases)
                            }
                            .font(.footnote.weight(.semibold))
                            .textCase(nil)
                        }
                    }
                }
            }
            .navigationTitle("Paste Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Paste") {
                        Self.savedParts = parts
                        state.pastePageLook(parts, to: targets)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(parts.isEmpty || targets.isEmpty)
                }
            }
        }
        .onAppear {
            let current = state.currentPageIndex
            targets = allOtherPages || sourceIndex == current ? otherPages : [current]
        }
    }

    private var sourceIndex: Int? { state.copiedPageNumber.map { $0 - 1 } }

    /// Every page except the one the settings came from.
    private var otherPages: Set<Int> { Set(state.pages.indices.filter { $0 != sourceIndex }) }

    private func partRow(_ part: PageLookPart, detail: String) -> some View {
        let on = parts.contains(part)
        return Button {
            if on { parts.remove(part) } else { parts.insert(part) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: part.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.accentColor)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(part.rawValue).foregroundColor(.primary)
                    Text(detail).font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(on ? .accentColor : .secondary.opacity(0.5))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    private var pageGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: 10)], spacing: 10) {
            ForEach(state.pages.indices, id: \.self) { i in
                let isSource = i == sourceIndex
                let on = targets.contains(i)
                Button {
                    if on { targets.remove(i) } else { targets.insert(i) }
                } label: {
                    VStack(spacing: 2) {
                        Text("\(i + 1)")
                            .font(.system(size: 16, weight: .semibold).monospacedDigit())
                        if isSource {
                            Image(systemName: "doc.on.doc").font(.system(size: 9, weight: .semibold))
                        }
                    }
                    .foregroundColor(on ? .white : (isSource ? .secondary : .primary))
                    .frame(width: 46, height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(on ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.06)))
                    )
                }
                .buttonStyle(.plain)
                .disabled(isSource)
                .accessibilityLabel(isSource ? "Page \(i + 1), copied from" : "Page \(i + 1)")
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.vertical, 4)
    }

    /// What the clipboard holds for a part, in a few words.
    private func detail(_ part: PageLookPart, _ clip: CopiedPageLook) -> String {
        let s = clip.style, l = clip.look
        switch part {
        case .layout:
            let lanes = s.isRows ? "row" : "column"
            return "\(s.numCols) \(lanes)\(s.numCols == 1 ? "" : "s") · spacing \(Int(s.gap)) · corners \(Int(s.cornerRadius))"
        case .background:
            return s.backgroundKind.rawValue
        case .border:
            return s.borderThickness == 0 ? "None" : "\(s.borderStyle.rawValue) · \(Int(s.borderThickness))"
        case .canvas:
            return "Margin \(Int(l.canvasMargin)) · \(Int(l.canvasRotation))°"
        case .frame:
            return l.canvasFrame?.displayName ?? "None"
        case .overlays:
            let n = l.overlayLayers.count
            return n == 0 ? "None" : "\(n) layer\(n == 1 ? "" : "s")"
        case .edits:
            let n = l.effects.values.filter { $0 != 0 }.count + l.hsl.shifts.count
                + (l.calibration == CameraCalibration() ? 0 : 1)
            return n == 0 ? "None" : "\(n) adjustment\(n == 1 ? "" : "s")"
        case .filter:
            return l.colorFilter == .none ? "None" : "\(l.colorFilter.title) · \(Int(l.filterStrength))%"
        }
    }

    private static let partsKey = "pastePageLookParts"

    /// The parts chosen last time (all of them at first).
    static var savedParts: Set<PageLookPart> {
        get {
            guard let raw = UserDefaults.standard.stringArray(forKey: partsKey) else { return Set(PageLookPart.allCases) }
            return Set(raw.compactMap(PageLookPart.init(rawValue:)))
        }
        set { UserDefaults.standard.set(newValue.map(\.rawValue), forKey: partsKey) }
    }
}
