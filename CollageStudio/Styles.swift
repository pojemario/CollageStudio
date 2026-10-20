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
        StylePreset(name: "Instant",
                    style: style(background: color(0.97, 0.96, 0.93), gap: 28, rounding: 0),
                    effects: ["Fade": 10, "Grain": 25, "Vignette": 15],
                    filter: "brownie", filterStrength: 45),
        StylePreset(name: "Magazine", style: style(background: .white, gap: 4, rounding: 0),
                    effects: ["Contrast": 15, "Clarity": 15]),
        StylePreset(name: "Film Strip",
                    style: style(background: color(0.08, 0.08, 0.08), gap: 14, rounding: 3),
                    effects: ["Grain": 35, "Vignette": 30, "Halation": 25],
                    filter: "classicNegative", filterStrength: 80),
        StylePreset(name: "Warm Film",
                    style: style(background: color(0.98, 0.95, 0.89), gap: 16, rounding: 12),
                    effects: ["Grain": 20], filter: "portra400"),
        StylePreset(name: "Pastel",
                    style: style(background: color(1, 0.92, 0.93), gap: 22, rounding: 34,
                                 kind: .gradient, second: color(0.88, 0.89, 1)),
                    effects: ["Fade": 15, "Temperature": 8]),
        StylePreset(name: "Moody",
                    style: style(background: color(0.18, 0.18, 0.2), gap: 12, rounding: 10),
                    effects: ["Vignette": 40, "Contrast": 10, "Fade": 8],
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
              var list = try? JSONDecoder().decode([StylePreset].self, from: data) else { return [] }
        // Fade went from ±100 to ±50 for the same look: older saved styles halve theirs, once.
        if !UserDefaults.standard.bool(forKey: fadeKey) {
            for i in list.indices { if let f = list[i].effects["Fade"] { list[i].effects["Fade"] = (f / 2).rounded() } }
            store(list)
            UserDefaults.standard.set(true, forKey: fadeKey)
        }
        return list
    }
    private static let fadeKey = "savedStylesFadeHalved"

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
            let s = e.span
            return min(max((effects[e] ?? 0) / s, r.lowerBound / s), r.upperBound / s)
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
            case .color:
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

// MARK: - Auto (Edit → Auto)

/// Balances a page like the Photos app's Auto: from all of the page's
/// photos together (the Edit sliders are one set per page), it sets the
/// Light and Color sliders so grays are neutral, the brightness sits in the
/// middle, clipped highlights and blocked shadows come back, the white and
/// black points are clean, contrast is moderate and flat colors get a lift.
/// Each slider is chosen by simulating what it does to sample pixels (the
/// same math the page uses), so the result lands where intended. The
/// filter, HSL and calibration stay as they are.
enum AutoAdjust {
    typealias Pixel = (r: Double, g: Double, b: Double)

    /// The sliders Auto sets: every Edit slider (Light, Color, Detail).
    /// HSL and calibration stay as they are.
    static let controlled: [CollageEffect] = CollageEffect.adjustments

    /// Pixels looked at for the whole page: enough for steady statistics,
    /// few enough that the slider search is instant.
    static let pageSampleBudget = 4000

    /// Up to `side`×`side` pixels of a picture, as sRGB 0…1.
    nonisolated static func samples(_ image: PlatformImage, side: Int = 72) -> [Pixel] {
        #if canImport(UIKit)
        guard let cg = image.cgImage else { return [] }
        #else
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }
        #endif
        let aspect = Double(cg.width) / Double(max(cg.height, 1))
        let w = max(Int(aspect >= 1 ? Double(side) : Double(side) * aspect), 8)
        let h = max(Int(aspect >= 1 ? Double(side) / aspect : Double(side)), 8)
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var out: [Pixel] = []
        out.reserveCapacity(w * h)
        for i in stride(from: 0, to: bytes.count, by: 4) where bytes[i + 3] > 200 {
            out.append((Double(bytes[i]) / 255, Double(bytes[i + 1]) / 255, Double(bytes[i + 2]) / 255))
        }
        return out
    }

    /// Slider values (Light and Color) that balance these pixels.
    nonisolated static func values(for pixels: [Pixel]) -> [CollageEffect: Double] {
        guard pixels.count > 200 else { return [:] }
        var v: [CollageEffect: Double] = [:]
        let ys0 = pixels.map(luma)

        // 1. White balance on the near-neutral pixels: most of a cast goes,
        // a little stays (a sunset should still feel warm).
        let neutrals = pixels.filter { p in
            let y = luma(p), s = saturation(p)
            return s < 0.22 && y > 0.15 && y < 0.92
        }
        if neutrals.count > pixels.count / 30 {
            let t = best(-40...40) { t in
                let m = mean(neutrals.map { simulate($0, v.merging([.temperature: t]) { $1 }) })
                return abs(m.r - m.b) * 0.72 + abs(t) * 0.0002
            }
            v[.temperature] = t * 0.75
            // (Tint gentler: foliage among the "neutrals" reads as a green cast.)
            let tint = best(-20...20) { k in
                let m = mean(neutrals.map { simulate($0, v.merging([.tint: k]) { $1 }) })
                return abs(m.g - (m.r + m.b) / 2) + abs(k) * 0.0002
            }
            v[.tint] = tint * 0.5
        }

        // 2. Exposure: the median a little under middle gray in sRGB terms;
        // low-key scenes are lifted less.
        let median0 = percentile(pixels.map(luma), 0.5)
        let target = min(max(0.44 + (median0 - 0.44) * 0.35, 0.36), 0.52)
        v[.exposure] = best(-50...50) { e in
            abs(percentile(pixels.map { luma(simulate($0, v.merging([.exposure: e]) { $1 })) }, 0.5) - target)
                + abs(e) * 0.0004
        }

        // 3. Highlights back if a lot sits near white; shadows open if the
        // dark end is blocked up.
        var ys = pixels.map { luma(simulate($0, v)) }
        let bright = Double(ys.filter { $0 > 0.93 }.count) / Double(ys.count)
        if bright > 0.015 { v[.highlights] = -min(65, (bright - 0.01) * 450) }
        let p10 = percentile(ys, 0.10)
        if p10 < 0.10 { v[.shadows] = min(55, (0.12 - p10) * 420) }

        // 4. White and black points, only nudged: each step has to earn its
        // keep (photos often have no true white or black, and that's fine).
        v[.whites] = best(-30...30) { w in
            abs(percentile(pixels.map { luma(simulate($0, v.merging([.whites: w]) { $1 })) }, 0.995) - 0.96)
                + abs(w) * 0.0015
        }
        v[.blacks] = best(-30...30) { b in
            abs(percentile(pixels.map { luma(simulate($0, v.merging([.blacks: b]) { $1 })) }, 0.005) - 0.035)
                + abs(b) * 0.0015
        }

        // 5. Contrast only when the tones are clearly flat or harsh: the
        // middle half spanning about 0.22–0.38 is left alone.
        let ys5 = pixels.map { luma(simulate($0, v)) }
        let iqr = percentile(ys5, 0.75) - percentile(ys5, 0.25)
        if iqr < 0.22 || iqr > 0.38 {
            let goal = iqr < 0.22 ? 0.24 : 0.36
            v[.contrast] = best(-15...20) { c in
                let ys = pixels.map { luma(simulate($0, v.merging([.contrast: c]) { $1 })) }
                return abs(percentile(ys, 0.75) - percentile(ys, 0.25) - goal) + abs(c) * 0.001
            }
        }

        // 6. Detail: a little clarity for flat pages, dehaze when the blacks
        // were washed out to begin with.
        if iqr < 0.26 { v[.clarity] = min(15, (0.26 - iqr) * 150 + 5) }
        let black0 = percentile(ys0, 0.01)
        if black0 > 0.09 { v[.dehaze] = min(25, (black0 - 0.07) * 160) }

        // 7. Vibrance for flat colors (gently down if they're loud).
        ys = pixels.map { luma(simulate($0, v)) }
        let sats = pixels.map { saturation(simulate($0, v)) }
        let mids = zip(ys, sats).filter { $0.0 > 0.12 && $0.0 < 0.9 }.map(\.1)
        if !mids.isEmpty {
            let s = mids.reduce(0, +) / Double(mids.count)
            if s < 0.30 { v[.vibrance] = min(35, (0.30 - s) * 160) }
            else if s > 0.50 { v[.vibrance] = max(-15, (0.50 - s) * 60) }
        }

        return v.mapValues { $0.rounded() }.filter { $0.value != 0 }
    }

    // MARK: Simulation (as the page does it)

    /// One pixel through the Basic tone (exposure … vibrance), Contrast, and
    /// the Temperature / Tint washes.
    nonisolated static func simulate(_ p: Pixel, _ v: [CollageEffect: Double]) -> Pixel {
        func amount(_ e: CollageEffect) -> Double { min(max((v[e] ?? 0) / e.span, -1), 1) }
        let tone = BasicTone(exposure: amount(.exposure), highlights: amount(.highlights), shadows: amount(.shadows),
                             whites: amount(.whites), blacks: amount(.blacks), vibrance: amount(.vibrance))
        var c = tone.isColorIdentity ? p : tone.apply(p.r, p.g, p.b)
        // SwiftUI .contrast: around mid gray.
        let k = 1 + 0.5 * amount(.contrast)
        if k != 1 { c = (clamp((c.r - 0.5) * k + 0.5), clamp((c.g - 0.5) * k + 0.5), clamp((c.b - 0.5) * k + 0.5)) }
        let t = amount(.temperature), n = amount(.tint)
        if t != 0 { c = softLight(c, t > 0 ? (1, 0.55, 0.12) : (0.15, 0.45, 1), opacity: 0.65 * abs(t)) }
        if n != 0 { c = softLight(c, n > 0 ? (0.95, 0.2, 0.75) : (0.25, 0.85, 0.3), opacity: 0.55 * abs(n)) }
        return c
    }

    nonisolated private static func softLight(_ b: Pixel, _ s: Pixel, opacity a: Double) -> Pixel {
        func ch(_ b: Double, _ s: Double) -> Double {
            let blended: Double
            if s <= 0.5 {
                blended = b - (1 - 2 * s) * b * (1 - b)
            } else {
                let d = b <= 0.25 ? ((16 * b - 12) * b + 4) * b : b.squareRoot()
                blended = b + (2 * s - 1) * (d - b)
            }
            return b + (blended - b) * a
        }
        return (ch(b.r, s.r), ch(b.g, s.g), ch(b.b, s.b))
    }

    // MARK: Helpers

    nonisolated private static func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
    nonisolated private static func luma(_ p: Pixel) -> Double { 0.2126 * p.r + 0.7152 * p.g + 0.0722 * p.b }
    nonisolated private static func saturation(_ p: Pixel) -> Double {
        let mx = max(p.r, p.g, p.b), mn = min(p.r, p.g, p.b)
        return mx > 0 ? (mx - mn) / mx : 0
    }
    nonisolated private static func mean(_ ps: [Pixel]) -> Pixel {
        let n = Double(max(ps.count, 1))
        return (ps.reduce(0) { $0 + $1.r } / n, ps.reduce(0) { $0 + $1.g } / n, ps.reduce(0) { $0 + $1.b } / n)
    }
    nonisolated private static func percentile(_ xs: [Double], _ q: Double) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        return s[min(max(Int(Double(s.count - 1) * q), 0), s.count - 1)]
    }
    /// The slider value in `range` with the lowest cost: a coarse pass, then
    /// a fine one around it.
    nonisolated private static func best(_ range: ClosedRange<Double>, cost: (Double) -> Double) -> Double {
        // Steps of 10, then 3 around the best, then 1: ~20 tries, not 100.
        var bestX = 0.0, bestC = cost(0)
        func scan(_ from: Double, _ to: Double, _ step: Double) {
            for x in stride(from: max(from, range.lowerBound), through: min(to, range.upperBound), by: step) where x != bestX {
                let c = cost(x)
                if c < bestC { bestC = c; bestX = x }
            }
        }
        scan(range.lowerBound, range.upperBound, 10)
        scan(bestX - 9, bestX + 9, 3)
        scan(bestX - 2, bestX + 2, 1)
        return bestX
    }
}

/// What Auto did on a page: the Edit sliders before it, and what it set.
struct AutoApplied {
    let before: [CollageEffect: Double]
    let after: [CollageEffect: Double]
}

extension CollageState {
    /// The Edit sliders being worked on (Light, Color, Detail): the photo
    /// being edited, else the page on screen.
    private var editSliders: [CollageEffect: Double] {
        editEffects.filter { AutoAdjust.controlled.contains($0.key) && $0.value != 0 }
    }

    /// What Auto works on: the photo being edited, else the page.
    private var autoTargetId: UUID { photoEditTargetId ?? currentPage.id }

    /// Auto is on here: it was pressed and nothing changed since.
    var isAutoOn: Bool {
        guard let applied = autoApplied[autoTargetId] else { return false }
        return editSliders == applied.after
    }

    /// Edit → Auto. Off: balances the page from all of its photos together
    /// (or, in Edit Photo, that photo)
    /// (remembering the sliders as they were). On: puts those back. Moving a
    /// slider after Auto turns it off again, ready to be pressed anew.
    func toggleAuto() {
        let pageId = autoTargetId
        if isAutoOn, let applied = autoApplied[pageId] {
            setEditSliders(applied.before)
            autoApplied[pageId] = nil
            return
        }
        // One photo (Edit Photo), or all of the page's.
        let photos = photoEditTarget.map { [$0.proxy] }
            ?? images.filter { !$0.isText && !$0.isPlaceholder }.map(\.proxy)
        guard !photos.isEmpty, !isAutoAdjusting else { return }
        isAutoAdjusting = true
        let before = editSliders
        Task {
            let values = await Task.detached(priority: .userInitiated) {
                // One sample of the whole page, every photo weighted the same.
                let side = Int((Double(AutoAdjust.pageSampleBudget) / Double(photos.count)).squareRoot())
                let pixels = photos.flatMap { AutoAdjust.samples($0, side: min(max(side, 16), 72)) }
                return AutoAdjust.values(for: pixels)
            }.value
            isAutoAdjusting = false
            guard autoTargetId == pageId else { return }
            Diagnostics.log("auto \(values.map { "\($0.key.rawValue) \(Int($0.value))" }.sorted().joined(separator: ", "))")
            setEditSliders(values)
            autoApplied[pageId] = AutoApplied(before: before, after: editSliders)
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        }
    }

    /// Replaces every Edit slider at once (one redraw, one undo step).
    private func setEditSliders(_ values: [CollageEffect: Double]) {
        var e = editEffects
        for effect in AutoAdjust.controlled { e[effect] = values[effect] }
        withAnimation(.easeInOut(duration: 0.25)) { editEffects = e.filter { $0.value != 0 } }
    }
}
