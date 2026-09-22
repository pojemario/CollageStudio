import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

// Everything here renders with plain SwiftUI modifiers and blend modes, which
// ImageRenderer honors — so the export matches the screen. (One trap:
// `.saturation(0)` is ignored by ImageRenderer; `.grayscale` is not.)

// MARK: - Tone (per-pixel color adjustments)

/// The effects that are pure color math — B&W and the contrast side of
/// fade (negative fade adds contrast and saturation instead) — applied to
/// the collage and to its background color alike.
struct EffectToning: ViewModifier {
    @ObservedObject var state: CollageState
    let enabled: Bool

    func body(content: Content) -> some View {
        let fade = enabled ? state.effectAmount(.fade) : 0
        let bw = enabled ? state.effectAmount(.blackWhite) : 0
        content
            .grayscale(bw)
            .saturation(1 - 0.4 * fade)
            .contrast(1 - 0.45 * fade)
            .brightness(0.06 * fade)
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
                               center: .center,
                               startRadius: longEdge * (0.30 - 0.12 * vignette),
                               endRadius: longEdge * 0.68)
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

/// One intensity slider per effect (double-tap a label or value to zero it).
struct EffectsPanel: View {
    @EnvironmentObject var state: CollageState

    var body: some View {
        VStack(spacing: 10) {
            ForEach(CollageEffect.allCases) { effect in
                LabeledSlider(label: effect.title,
                              value: Binding(
                                get: { state.effects[effect] ?? 0 },
                                set: { state.effects[effect] = $0 }),
                              range: effect.range, step: 1, format: "%.0f", resetValue: 0)
            }
            HStack(spacing: 8) {
                EffectShuffleButton().panelChrome(state, keep: "Shuffle")
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
                    ForEach(CollageEffect.allCases) { effect in
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
        .background(Color.accentColor)
        .cornerRadius(10)
    }
}
