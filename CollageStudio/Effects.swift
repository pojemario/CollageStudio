import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

// Everything here renders with plain SwiftUI modifiers and blend modes, which
// ImageRenderer honors — so the export matches the screen. (One trap:
// `.saturation(0)` is ignored by ImageRenderer; `.grayscale` is not.)

// MARK: - Tone (per-pixel color adjustments)

/// The effects that are pure color math — brightness, contrast and the
/// contrast side of fade (negative fade adds contrast and saturation
/// instead) — applied to the collage and to its background color alike.
/// Never to overlays or the frame: those are drawn outside it.
struct EffectToning: ViewModifier {
    @ObservedObject var state: CollageState
    let enabled: Bool

    func body(content: Content) -> some View {
        let fade = enabled ? state.effectAmount(.fade) : 0
        let brightness = enabled ? state.effectAmount(.brightness) : 0
        let contrast = enabled ? state.effectAmount(.contrast) : 0
        content
            .saturation(1 - 0.4 * fade)
            .contrast((1 - 0.45 * fade) * (1 + 0.5 * contrast))
            .brightness(0.06 * fade + 0.2 * brightness)
    }
}

// MARK: - Layers (effects that add something on top)

/// Stacked right above the collage, under the overlays and the frame.
/// `window` is the content area (the frame's opening, or the whole canvas
/// without a frame): the layers are masked to it, so nothing lands on the
/// frame even where its PNG is see-through.
struct EffectLayers: View {
    @EnvironmentObject var state: CollageState
    @ObservedObject var maps: EffectMaps
    let canvasSize: CGSize
    let window: CGRect

    var body: some View {
        let temperature = state.effectAmount(.temperature)
        let fade = state.effectAmount(.fade)
        let glow = state.effectAmount(.glow)
        let halation = state.effectAmount(.halation)
        let vignette = state.effectAmount(.vignette)
        let grain = state.effectAmount(.grain)
        let longEdge = max(window.width, window.height)

        ZStack {
            // Temperature: an amber or blue wash, soft-light blended so it
            // shifts the midtones and leaves blacks and whites mostly alone.
            if temperature != 0 {
                (temperature > 0 ? Color(red: 1, green: 0.55, blue: 0.12)
                                 : Color(red: 0.15, green: 0.45, blue: 1))
                    .opacity(0.65 * abs(temperature))
                    .blendMode(.softLight)
            }
            // Fade: a screened haze lifts the blacks into a matte gray.
            if fade > 0 {
                Color(white: 0.34 * fade).blendMode(.screen)
            }
            if glow > 0, let map = maps.glow {
                mapLayer(map).opacity(glow).blendMode(.screen)
            }
            if halation > 0, let map = maps.halation {
                mapLayer(map).opacity(halation).blendMode(.screen)
            }
            if vignette > 0 {
                // Starts closer to the center and goes fully dark at the
                // corners when maxed.
                RadialGradient(colors: [.clear, .black.opacity(0.5 * vignette), .black.opacity(1.0 * vignette)],
                               center: UnitPoint(x: window.midX / max(canvasSize.width, 1),
                                                 y: window.midY / max(canvasSize.height, 1)),
                               startRadius: longEdge * (0.30 - 0.12 * vignette),
                               endRadius: longEdge * 0.68)
            }
            if grain > 0, let texture = PlatformImage.named("EffectGrain") {
                mapLayer(texture).opacity(0.75 * grain).blendMode(.overlay)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .mask(alignment: .topLeading) {
            Rectangle()
                .frame(width: window.width, height: window.height)
                .offset(x: window.minX, y: window.minY)
        }
        .allowsHitTesting(false)
    }

    private func mapLayer(_ image: PlatformImage) -> some View {
        Group {
            #if canImport(UIKit)
            Image(uiImage: image).resizable()
            #else
            Image(nsImage: image).resizable()
            #endif
        }
        .scaledToFill()
        .frame(width: canvasSize.width, height: canvasSize.height)
        .clipped()
    }
}

// MARK: - Highlight maps for glow & halation

/// Blurred-highlight images derived from a snapshot of the collage (see
/// CollageState.refreshEffectMaps). Screen-blended over the canvas they read
/// as light bleeding out of the bright areas: wide and neutral for glow,
/// tight and red-orange for halation.
final class EffectMaps: ObservableObject {
    @Published private(set) var glow: PlatformImage?
    @Published private(set) var halation: PlatformImage?

    private let context = CIContext()

    func clear() {
        if glow != nil { glow = nil }
        if halation != nil { halation = nil }
    }

    func update(from snapshot: CGImage, glow wantGlow: Bool, halation wantHalation: Bool) {
        let source = CIImage(cgImage: snapshot)
        let longEdge = max(source.extent.width, source.extent.height)

        glow = wantGlow
            ? render(highlights(of: source, from: 0.35), blur: longEdge * 0.045, extent: source.extent)
            : nil

        if wantHalation {
            // Film halation: light scattering back through the base exposes
            // mostly the red layer — luminance in, red-orange out.
            let tint = CIFilter.colorMatrix()
            tint.inputImage = highlights(of: source, from: 0.6)
            tint.rVector = CIVector(x: 0.9, y: 0.6, z: 0.2, w: 0)
            tint.gVector = CIVector(x: 0.22, y: 0.14, z: 0.05, w: 0)
            tint.bVector = CIVector(x: 0.05, y: 0.03, z: 0.01, w: 0)
            tint.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            halation = render(tint.outputImage, blur: longEdge * 0.016, extent: source.extent)
        } else {
            halation = nil
        }
    }

    /// Everything darker than `threshold` goes to black; the rest ramps up.
    private func highlights(of image: CIImage, from threshold: CGFloat) -> CIImage? {
        let curve = CIFilter.toneCurve()
        curve.inputImage = image
        curve.point0 = CGPoint(x: 0, y: 0)
        curve.point1 = CGPoint(x: threshold, y: 0)
        curve.point2 = CGPoint(x: threshold + (1 - threshold) * 0.45, y: 0.22)
        curve.point3 = CGPoint(x: threshold + (1 - threshold) * 0.8, y: 0.66)
        curve.point4 = CGPoint(x: 1, y: 1)
        return curve.outputImage
    }

    private func render(_ image: CIImage?, blur radius: CGFloat, extent: CGRect) -> PlatformImage? {
        guard let image else { return nil }
        let blurred = image.clampedToExtent()
            .applyingGaussianBlur(sigma: radius)
            .cropped(to: extent)
        guard let cg = context.createCGImage(blurred, from: extent) else { return nil }
        #if canImport(UIKit)
        return UIImage(cgImage: cg)
        #else
        return NSImage(cgImage: cg, size: extent.size)
        #endif
    }
}

// MARK: - HSL grading

/// Per-color hue / saturation / luminance, baked into a color cube and run
/// over the pictures with Core Image (so the export matches the screen).
/// The background color goes through the same math directly.
enum HSLGrader {
    private static let context = CIContext()
    private static let cubeSize = 32
    /// Hue shift at ±100, in degrees.
    private static let maxHueShift = 30.0

    static func apply(_ hsl: HSLAdjustments, to image: PlatformImage) -> PlatformImage {
        #if canImport(UIKit)
        guard let cg = image.cgImage else { return image }
        #else
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        #endif
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        let filter = CIFilter.colorCubeWithColorSpace()
        filter.inputImage = CIImage(cgImage: cg)
        filter.cubeDimension = Float(cubeSize)
        filter.cubeData = cubeData(hsl)
        filter.colorSpace = sRGB
        guard let output = filter.outputImage,
              let graded = context.createCGImage(output, from: output.extent) else { return image }
        #if canImport(UIKit)
        return UIImage(cgImage: graded, scale: image.scale, orientation: image.imageOrientation)
        #else
        return NSImage(cgImage: graded, size: image.size)
        #endif
    }

    static func apply(_ hsl: HSLAdjustments, to color: Color) -> Color {
        guard !hsl.isIdentity else { return color }
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return color }
        #else
        guard let ns = NSColor(color).usingColorSpace(.sRGB) else { return color }
        let r = ns.redComponent, g = ns.greenComponent, b = ns.blueComponent, a = ns.alphaComponent
        #endif
        let out = adjust(Double(r), Double(g), Double(b), hsl)
        return Color(.sRGB, red: out.r, green: out.g, blue: out.b, opacity: Double(a))
    }

    private static func cubeData(_ hsl: HSLAdjustments) -> Data {
        let n = cubeSize
        var values = [Float]()
        values.reserveCapacity(n * n * n * 4)
        for bi in 0..<n {
            for gi in 0..<n {
                for ri in 0..<n {
                    let out = adjust(Double(ri) / Double(n - 1), Double(gi) / Double(n - 1),
                                     Double(bi) / Double(n - 1), hsl)
                    values += [Float(out.r), Float(out.g), Float(out.b), 1]
                }
            }
        }
        return values.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// One sRGB color through the per-band shifts. A pixel's hue blends the
    /// two nearest bands; grays (low chroma) are left alone so neutral
    /// areas never pick up a tint.
    static func adjust(_ r: Double, _ g: Double, _ b: Double,
                       _ hsl: HSLAdjustments) -> (r: Double, g: Double, b: Double) {
        let maxC = max(r, g, b), minC = min(r, g, b)
        let chroma = maxC - minC
        guard chroma > 0.0001 else { return (r, g, b) }

        var l = (maxC + minC) / 2
        var s = chroma / (1 - abs(2 * l - 1))
        var h: Double
        if maxC == r { h = (g - b) / chroma }
        else if maxC == g { h = (b - r) / chroma + 2 }
        else { h = (r - g) / chroma + 4 }
        h = (h * 60).truncatingRemainder(dividingBy: 360)
        if h < 0 { h += 360 }

        // The two bands around this hue, blended smoothly.
        let bands = HSLBand.allCases
        var lower = bands[bands.count - 1], upper = bands[0]
        var lowerHue = lower.hue - 360, upperHue = upper.hue
        for (i, band) in bands.enumerated() where band.hue <= h {
            lower = band
            lowerHue = band.hue
            upper = i + 1 < bands.count ? bands[i + 1] : bands[0]
            upperHue = i + 1 < bands.count ? upper.hue : 360
        }
        let t = (h - lowerHue) / (upperHue - lowerHue)
        let wUpper = (1 - cos(.pi * t)) / 2, wLower = 1 - wUpper
        let a = hsl[lower], c = hsl[upper]
        // Fade the adjustment out toward gray.
        let strength = min(1, chroma / 0.15)
        let dh = (a.hue * wLower + c.hue * wUpper) / 100 * strength
        let ds = (a.saturation * wLower + c.saturation * wUpper) / 100 * strength
        let dl = (a.luminance * wLower + c.luminance * wUpper) / 100 * strength

        h = (h + dh * maxHueShift + 360).truncatingRemainder(dividingBy: 360)
        s = min(max(s * (1 + ds), 0), 1)
        l = dl >= 0 ? l + (1 - l) * dl * 0.5 : l * (1 + dl * 0.5)

        // Back to RGB.
        let c2 = (1 - abs(2 * l - 1)) * s
        let x = c2 * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c2 / 2
        let (r1, g1, b1): (Double, Double, Double)
        switch h {
        case ..<60:  (r1, g1, b1) = (c2, x, 0)
        case ..<120: (r1, g1, b1) = (x, c2, 0)
        case ..<180: (r1, g1, b1) = (0, c2, x)
        case ..<240: (r1, g1, b1) = (0, x, c2)
        case ..<300: (r1, g1, b1) = (x, 0, c2)
        default:     (r1, g1, b1) = (c2, 0, x)
        }
        return (r1 + m, g1 + m, b1 + m)
    }
}

// MARK: - Per-picture grading

/// Runs a ContentGrade over a picture: the HSL color cube, then clarity
/// (wide unsharp mask for local contrast, or a blur blend to soften), then
/// sharpness (fine unsharp mask). Radii scale with the picture's size, so
/// the canvas proxy and the full-resolution export look the same.
enum ContentGrader {
    private static let context = CIContext()

    static func apply(_ grade: ContentGrade, to image: PlatformImage) -> PlatformImage {
        guard !grade.isIdentity else { return image }
        var source = image
        if !grade.hsl.isIdentity { source = HSLGrader.apply(grade.hsl, to: source) }
        guard grade.clarity != 0 || grade.sharpness > 0 else { return source }

        #if canImport(UIKit)
        guard let cg = source.cgImage else { return source }
        #else
        guard let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return source }
        #endif
        let input = CIImage(cgImage: cg)
        let extent = input.extent
        let longEdge = max(extent.width, extent.height)
        var out = input

        if grade.clarity > 0 {
            let f = CIFilter.unsharpMask()
            f.inputImage = out.clampedToExtent()
            f.radius = Float(longEdge * 0.025)
            f.intensity = Float(grade.clarity * 0.7)
            out = (f.outputImage ?? out).cropped(to: extent)
        } else if grade.clarity < 0 {
            let blurred = out.clampedToExtent()
                .applyingGaussianBlur(sigma: Double(longEdge * 0.008))
                .cropped(to: extent)
            let f = CIFilter.dissolveTransition()
            f.inputImage = out
            f.targetImage = blurred
            f.time = Float(-grade.clarity * 0.6)
            out = (f.outputImage ?? out).cropped(to: extent)
        }

        if grade.sharpness > 0 {
            let f = CIFilter.unsharpMask()
            f.inputImage = out.clampedToExtent()
            f.radius = Float(max(longEdge * 0.0018, 0.8))
            f.intensity = Float(grade.sharpness * 1.4)
            out = (f.outputImage ?? out).cropped(to: extent)
        }

        guard let rendered = context.createCGImage(out, from: extent) else { return source }
        #if canImport(UIKit)
        return UIImage(cgImage: rendered, scale: source.scale, orientation: source.imageOrientation)
        #else
        return NSImage(cgImage: rendered, size: source.size)
        #endif
    }
}

// MARK: - Effects tab / sidebar section

/// One intensity slider per effect (double-tap a label or value to zero it),
/// with the per-color HSL controls on a second page.
struct EffectsPanel: View {
    @EnvironmentObject var state: CollageState
    enum Page: String, CaseIterable { case edit = "Edit", effects = "Effects", hsl = "HSL" }
    @State private var page: Page = .edit
    @State private var band: HSLBand = .red

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(Page.allCases, id: \.self) { p in
                    PackChip(title: p.rawValue, isActive: page == p) { page = p }
                }
                Spacer()
            }
            .panelChrome(state)

            switch page {
            case .edit: editControls
            case .effects: effectControls
            case .hsl: hslControls
            }
        }
    }

    private func sliders(_ group: [CollageEffect]) -> some View {
        ForEach(group) { effect in
            LabeledSlider(label: effect.title,
                          value: Binding(
                            get: { state.effects[effect] ?? 0 },
                            set: { state.effects[effect] = $0 }),
                          range: effect.range, step: 1, format: "%.0f", resetValue: 0)
        }
    }

    private func resetButton(_ group: [CollageEffect]) -> some View {
        ActionButton(label: "Reset", sf: "arrow.counterclockwise", fillWidth: false) {
            state.resetEffects(in: group)
        }
        .disabled(!state.hasEffects(in: group))
        .opacity(state.hasEffects(in: group) ? 1 : 0.5)
        .panelChrome(state)
    }

    /// Basic corrections: temperature, brightness, contrast, clarity,
    /// sharpness.
    private var editControls: some View {
        VStack(spacing: 10) {
            sliders(CollageEffect.adjustments)
            HStack(spacing: 8) {
                Spacer()
                resetButton(CollageEffect.adjustments)
            }
        }
    }

    /// Looks: fade, halation, glow, vignette, grain.
    private var effectControls: some View {
        VStack(spacing: 10) {
            sliders(CollageEffect.looks)
            HStack(spacing: 8) {
                EffectShuffleButton().panelChrome(state, keep: "Shuffle")
                Spacer()
                resetButton(CollageEffect.looks)
            }
        }
    }

    private var hslControls: some View {
        VStack(spacing: 10) {
            // Band picker: a dot per color; a ring marks the selected one,
            // a small mark under it any band that has been adjusted.
            HStack(spacing: 0) {
                ForEach(HSLBand.allCases) { b in
                    Button { band = b } label: {
                        VStack(spacing: 3) {
                            Circle()
                                .fill(b.swatch)
                                .frame(width: 24, height: 24)
                                .padding(3)
                                .overlay(Circle().stroke(band == b ? Color.primary : .clear, lineWidth: 2))
                            Circle()
                                .fill(Color.primary.opacity(state.hsl[b].isZero ? 0 : 0.6))
                                .frame(width: 4, height: 4)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(b.title)
                }
            }
            .panelChrome(state)

            LabeledSlider(label: "Hue", value: shift(\.hue),
                          range: -100...100, step: 1, format: "%.0f", resetValue: 0,
                          trackColors: band.hueSweep)
            LabeledSlider(label: "Saturation", value: shift(\.saturation),
                          range: -100...100, step: 1, format: "%.0f", resetValue: 0)
            LabeledSlider(label: "Luminance", value: shift(\.luminance),
                          range: -100...100, step: 1, format: "%.0f", resetValue: 0)

        }
    }

    private func shift(_ key: WritableKeyPath<HSLShift, Double>) -> Binding<Double> {
        Binding(get: { state.hsl[band][keyPath: key] },
                set: { state.hsl[band][keyPath: key] = $0 })
    }
}

/// Shuffle for the Effects tab, styled like the Layout one: the left segment
/// randomizes the chosen effects, the gear picks which ones (all by default).
struct EffectShuffleButton: View {
    @EnvironmentObject var state: CollageState
    @State private var showOptions = false

    var body: some View {
        HStack(spacing: 0) {
            Button { state.shuffleEffects() } label: {
                Label("Shuffle", systemImage: "dice")
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                    .padding(.horizontal, 14)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(Color.white.opacity(0.35))
                .frame(width: 1)
                .padding(.vertical, 8)

            Button { showOptions = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14, weight: .semibold))
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
                    ForEach(CollageEffect.looks) { effect in
                        Toggle(effect.title, isOn: Binding(
                            get: { state.effectShuffleOptions.contains(effect) },
                            set: { on in
                                if on { state.effectShuffleOptions.insert(effect) }
                                else { state.effectShuffleOptions.remove(effect) }
                            }))
                            .toggleStyle(.switch)
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                    }
                }
                .padding(.bottom, 8)
                .frame(width: 230)
                .foregroundColor(.primary)
                .presentationCompactAdaptation(.popover)
            }
        }
        .foregroundColor(.white)
        .frame(height: 38)
        .appButtonBackground(prominent: true)
    }
}
