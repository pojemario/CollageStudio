import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

// Everything here renders with plain SwiftUI modifiers and blend modes, which
// ImageRenderer honors — so the export matches the screen. (One trap:
// `.saturation(0)` is ignored by ImageRenderer; `.grayscale` is not.)

// MARK: - Tone (per-pixel color adjustments)

/// The effects that are pure color math — B&W, sepia and the contrast side
/// of fade — applied to the collage and to its background color alike.
struct EffectToning: ViewModifier {
    @ObservedObject var state: CollageState
    let enabled: Bool

    func body(content: Content) -> some View {
        let fade = enabled ? state.effectAmount(.fade) : 0
        let bw = enabled ? state.effectAmount(.blackWhite) : 0
        let sepia = enabled ? state.effectAmount(.sepia) : 0
        content
            .grayscale(min(1, bw + sepia * 0.9))
            .colorMultiply(Color(red: 1, green: 1 - 0.14 * sepia, blue: 1 - 0.36 * sepia))
            .saturation(1 - 0.25 * fade)
            .contrast(1 - 0.24 * fade)
            .brightness(0.03 * fade + 0.05 * sepia)
    }
}

// MARK: - Layers (effects that add something on top)

/// Stacked right above the collage, under the overlays and the frame.
struct EffectLayers: View {
    @EnvironmentObject var state: CollageState
    @ObservedObject var maps: EffectMaps
    let canvasSize: CGSize

    var body: some View {
        let fade = state.effectAmount(.fade)
        let glow = state.effectAmount(.glow)
        let halation = state.effectAmount(.halation)
        let vignette = state.effectAmount(.vignette)
        let grain = state.effectAmount(.grain)
        let longEdge = max(canvasSize.width, canvasSize.height)

        ZStack {
            // Fade: a screened haze lifts the blacks into a matte gray.
            if fade > 0 {
                Color(white: 0.2 * fade).blendMode(.screen)
            }
            if glow > 0, let map = maps.glow {
                mapLayer(map).opacity(glow).blendMode(.screen)
            }
            if halation > 0, let map = maps.halation {
                mapLayer(map).opacity(halation).blendMode(.screen)
            }
            if vignette > 0 {
                RadialGradient(colors: [.clear, .black.opacity(0.85 * vignette)],
                               center: .center,
                               startRadius: longEdge * 0.30, endRadius: longEdge * 0.74)
            }
            if grain > 0, let texture = PlatformImage.named("EffectGrain") {
                mapLayer(texture).opacity(0.75 * grain).blendMode(.overlay)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
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

// MARK: - Effects tab / sidebar section

/// One intensity slider per effect (double-tap a value to zero it) plus a
/// reset for the whole set.
struct EffectsPanel: View {
    @EnvironmentObject var state: CollageState

    var body: some View {
        VStack(spacing: 10) {
            ForEach(CollageEffect.allCases) { effect in
                LabeledSlider(label: effect.title,
                              value: Binding(
                                get: { state.effects[effect] ?? 0 },
                                set: { state.effects[effect] = $0 }),
                              range: 0...100, step: 1, format: "%.0f", resetValue: 0)
            }
            HStack {
                Spacer()
                ActionButton(label: "Reset", sf: "arrow.counterclockwise", fillWidth: false) {
                    state.resetEffects()
                }
                .disabled(!state.hasEffects)
                .opacity(state.hasEffects ? 1 : 0.5)
                .panelChrome(state)
            }
        }
    }
}
