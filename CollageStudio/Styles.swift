import SwiftUI

/// A whole look in one tap: the Layout settings (all but the column count),
/// plus the Edit / Effects values and the filter.
struct StylePreset: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var style: PageStyle
    var effects: [String: Double] = [:]
    var filter: String = "none"
    var filterStrength: Double = 100
    var hsl: [String: [Double]] = [:]
    var calibration: [Double] = []

    var effectValues: [CollageEffect: Double] { effectsFromStorage(effects) }
    var colorFilter: ColorFilter { ColorFilter(storageKey: filter) }

    /// What the pictures get graded with under this look (for the preview).
    var grade: ContentGrade {
        CollageState.grade(effects: effectValues, hsl: HSLAdjustments(storage: hsl),
                           calibration: CameraCalibration(storage: calibration),
                           filter: colorFilter, filterStrength: filterStrength)
    }

    private static func color(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    private static func style(background: Color, gap: Double, rounding: Double,
                              border: Double = 0, borderColor: Color? = nil,
                              kind: BackgroundKind = .color, second: Color? = nil) -> PageStyle {
        var s = PageStyle()
        s.backgroundColor = background
        s.backgroundKind = kind
        if let second { s.backgroundColor2 = second }
        s.borderColor = borderColor ?? background
        s.linkBorderToBackground = borderColor == nil
        s.gap = gap
        s.cornerRadius = rounding
        s.borderThickness = border
        return s
    }

    /// The looks that come with the app.
    static let builtIns: [StylePreset] = [
        StylePreset(name: "Clean", style: style(background: .white, gap: 10, rounding: 20)),
        StylePreset(name: "Polaroid",
                    style: style(background: color(0.97, 0.96, 0.93), gap: 28, rounding: 0, kind: .paper),
                    effects: ["Fade": 20, "Grain": 25, "Vignette": 15],
                    filter: "brownie", filterStrength: 45),
        StylePreset(name: "Magazine", style: style(background: .white, gap: 4, rounding: 0),
                    effects: ["Contrast": 15, "Clarity": 15]),
        StylePreset(name: "Film Strip",
                    style: style(background: color(0.08, 0.08, 0.08), gap: 14, rounding: 3),
                    effects: ["Grain": 35, "Vignette": 30, "Halation": 25],
                    filter: "classicNegative", filterStrength: 80),
        StylePreset(name: "Portra",
                    style: style(background: color(0.98, 0.95, 0.89), gap: 16, rounding: 12),
                    effects: ["Grain": 20], filter: "portra400"),
        StylePreset(name: "Pastel",
                    style: style(background: color(1, 0.92, 0.93), gap: 22, rounding: 34,
                                 kind: .gradient, second: color(0.88, 0.89, 1)),
                    effects: ["Fade": 30, "Temperature": 8]),
        StylePreset(name: "Moody",
                    style: style(background: color(0.18, 0.18, 0.2), gap: 12, rounding: 10),
                    effects: ["Vignette": 40, "Contrast": 10, "Fade": 15],
                    filter: "melancholy", filterStrength: 90),
        StylePreset(name: "Cut Out",
                    style: style(background: color(0.93, 0.93, 0.95), gap: 18, rounding: 6,
                                 border: 8, borderColor: .white)),
    ]
}

/// The user's own looks, kept on the device.
enum SavedStyles {
    private static let key = "savedStyles"

    static func load() -> [StylePreset] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([StylePreset].self, from: data) else { return [] }
        return list
    }

    static func store(_ list: [StylePreset]) {
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: key) }
    }
}

extension CollageState {
    /// The grade for a set of Edit / Effects values, HSL, calibration and filter.
    nonisolated static func grade(effects: [CollageEffect: Double], hsl: HSLAdjustments, calibration: CameraCalibration,
                      filter: ColorFilter, filterStrength: Double) -> ContentGrade {
        func amount(_ e: CollageEffect) -> Double {
            let r = e.range
            return min(max((effects[e] ?? 0) / 100, r.lowerBound / 100), r.upperBound / 100)
        }
        return ContentGrade(calibration: calibration,
                            tone: BasicTone(exposure: amount(.exposure), highlights: amount(.highlights),
                                            shadows: amount(.shadows), whites: amount(.whites),
                                            blacks: amount(.blacks), vibrance: amount(.vibrance),
                                            saturation: amount(.saturation), dehaze: amount(.dehaze),
                                            texture: amount(.texture)),
                            filter: filter, filterStrength: filterStrength / 100, hsl: hsl,
                            clarity: amount(.clarity), sharpness: amount(.sharpness))
    }

    /// Puts a look on the current page (its column count stays) and on the
    /// collage-wide edits. Undo takes it back.
    func applyStylePreset(_ preset: StylePreset) {
        var style = preset.style
        style.numCols = numCols
        style.isRows = isRows
        withAnimation(.easeInOut(duration: 0.25)) {
            currentPage.style = style
            effects = preset.effectValues
            colorFilter = preset.colorFilter
            filterStrength = preset.filterStrength
            hsl = HSLAdjustments(storage: preset.hsl)
            calibration = CameraCalibration(storage: preset.calibration)
        }
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    /// The current look, to save under a name.
    func currentStylePreset(named name: String) -> StylePreset {
        StylePreset(name: name, style: currentPage.style, effects: effects.storage,
                    filter: colorFilter.storageKey, filterStrength: filterStrength,
                    hsl: hsl.storage, calibration: calibration.storage)
    }
}

/// The row of looks at the top of the Layout tab: "Save" first, then the
/// user's own looks, then the built-in ones.
struct StylePresetsRow: View {
    @EnvironmentObject var state: CollageState
    @State private var saved = SavedStyles.load()
    @State private var naming = false
    @State private var name = ""

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                Button {
                    name = ""
                    naming = true
                } label: {
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                            .frame(width: 52, height: 52)
                            .overlay {
                                Image(systemName: "plus")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.accentColor)
                            }
                        Text("Save")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.accentColor)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Save current style")

                ForEach(saved) { preset in
                    chip(preset)
                        .contextMenu {
                            Button(role: .destructive) {
                                saved.removeAll { $0.id == preset.id }
                                SavedStyles.store(saved)
                            } label: { Label("Remove", systemImage: "trash") }
                        }
                }
                ForEach(StylePreset.builtIns) { preset in
                    chip(preset)
                }
            }
            .padding(.vertical, 2)
        }
        .alert("Save Style", isPresented: $naming) {
            TextField("Name", text: $name)
            Button("Save") {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                saved.insert(state.currentStylePreset(named: trimmed.isEmpty ? "My Style" : trimmed), at: 0)
                SavedStyles.store(saved)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves the Layout settings, edits, effects and filter, to use on any collage.")
        }
        .panelChrome(state)
    }

    private func chip(_ preset: StylePreset) -> some View {
        Button { state.applyStylePreset(preset) } label: {
            VStack(spacing: 4) {
                StylePreview(preset: preset)
                    .frame(width: 52, height: 52)
                Text(preset.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .frame(width: 60)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(preset.name) style")
    }
}

/// A tiny collage in a look: its background, spacing, rounding and border,
/// with sample colors run through its edits and filter.
struct StylePreview: View {
    let preset: StylePreset

    private static let samples: [Color] = [
        Color(.sRGB, red: 0.45, green: 0.65, blue: 0.9),
        Color(.sRGB, red: 0.92, green: 0.72, blue: 0.6),
        Color(.sRGB, red: 0.42, green: 0.62, blue: 0.32),
        Color(.sRGB, red: 0.96, green: 0.76, blue: 0.36),
    ]

    var body: some View {
        let s = preset.style
        let grade = preset.grade
        let k: CGFloat = 52 / 600
        let gap = max(CGFloat(s.gap) * k * 2.2, 1.5)
        let radius = CGFloat(s.cornerRadius) * k * 1.4
        let border = s.borderThickness > 0 ? max(CGFloat(s.borderThickness) * k * 1.5, 1) : 0
        let colors = Self.samples.map { ContentGrader.apply(grade, to: $0) }
        let box = RoundedRectangle(cornerRadius: radius, style: .continuous)
        VStack(spacing: gap) {
            HStack(spacing: gap) {
                box.fill(colors[0]).overlay(box.strokeBorder(s.borderColor, lineWidth: border))
                box.fill(colors[1]).overlay(box.strokeBorder(s.borderColor, lineWidth: border))
            }
            HStack(spacing: gap) {
                box.fill(colors[2]).overlay(box.strokeBorder(s.borderColor, lineWidth: border))
                box.fill(colors[3]).overlay(box.strokeBorder(s.borderColor, lineWidth: border))
            }
        }
        .padding(gap)
        .background {
            let top = ContentGrader.apply(grade, to: s.backgroundColor)
            switch s.backgroundKind {
            case .gradient:
                LinearGradient(colors: [top, ContentGrader.apply(grade, to: s.backgroundColor2)],
                               startPoint: .top, endPoint: .bottom)
            case .photo:
                LinearGradient(colors: [colors[0].opacity(0.8), colors[3].opacity(0.8)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            case .color, .paper:
                top
            }
        }
        .overlay {
            // A hint of vignette / fade where the look has them.
            if (preset.effectValues[.vignette] ?? 0) > 0 {
                RadialGradient(colors: [.clear, .black.opacity(0.25)], center: .center, startRadius: 14, endRadius: 38)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.8))
    }
}
