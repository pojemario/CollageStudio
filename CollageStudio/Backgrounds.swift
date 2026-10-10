import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

/// What fills the collage behind (and between) the photos.
enum BackgroundKind: String, CaseIterable, Identifiable {
    case color = "Color"
    /// From the background color at the top to the second color below.
    case gradient = "Gradient"
    /// The page's first photo, blurred into a soft wash of its colors.
    case photo = "Photo"
    /// The background color with a fine paper grain.
    case paper = "Paper"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .color: return "square.fill"
        case .gradient: return "square.bottomhalf.filled"
        case .photo: return "photo"
        case .paper: return "doc.plaintext"
        }
    }
}

extension CollageState {
    var backgroundKind: BackgroundKind {
        get { currentPage.style.backgroundKind }
        set { currentPage.style.backgroundKind = newValue }
    }
    var backgroundColor2: Color {
        get { currentPage.style.backgroundColor2 }
        set { currentPage.style.backgroundColor2 = newValue }
    }
}

/// The page background, in any of its kinds, graded like the photos (the
/// toning effects are applied by the caller).
struct CollageBackground: View {
    @EnvironmentObject var state: CollageState

    var body: some View {
        let grade = state.contentGrade
        let color = ContentGrader.apply(grade, to: state.backgroundColor)
        switch state.backgroundKind {
        case .color:
            color
        case .gradient:
            LinearGradient(colors: [color, ContentGrader.apply(grade, to: state.backgroundColor2)],
                           startPoint: .top, endPoint: .bottom)
        case .paper:
            color.overlay {
                PaperTexture.image
                    .resizable()
                    .scaledToFill()
                    .blendMode(.multiply)
                    .opacity(0.55)
            }
            .clipped()
        case .photo:
            GeometryReader { geo in
                if let img = state.images.first(where: { $0.canProtrude }) {
                    let picture = state.gradedDisplayImage(for: img)
                    Group {
                        #if canImport(UIKit)
                        Image(uiImage: picture).resizable()
                        #else
                        Image(nsImage: picture).resizable()
                        #endif
                    }
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    // Blur relative to the canvas, so screen and export match.
                    .blur(radius: max(geo.size.width, geo.size.height) * 0.05, opaque: true)
                    .overlay(Color.white.opacity(0.12))
                    .clipped()
                } else {
                    color
                }
            }
        }
    }
}

/// A fine, soft paper grain (white with faint gray specks), made once.
enum PaperTexture {
    static let image: Image = {
        let size = 1024
        let noise = CIFilter.randomGenerator().outputImage?
            .cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
        let gray = noise?.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0, kCIInputContrastKey: 0.35, kCIInputBrightnessKey: 0.38,
        ])
        .applyingGaussianBlur(sigma: 0.7)
        .cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
        guard let gray, let cg = CIContext().createCGImage(gray, from: gray.extent) else { return Image(systemName: "square") }
        #if canImport(UIKit)
        return Image(uiImage: UIImage(cgImage: cg))
        #else
        return Image(nsImage: NSImage(cgImage: cg, size: NSSize(width: size, height: size)))
        #endif
    }()
}

/// Layout tab row: what kind of background, plus the gradient's second color.
struct BackgroundKindRow: View {
    @EnvironmentObject var state: CollageState

    var body: some View {
        HStack(spacing: 8) {
            Text("Fill")
                .font(.subheadline)
                .foregroundColor(.primary)
                .frame(width: 92, alignment: .leading)
            // The gradient's bottom color, in the swatch column.
            if state.backgroundKind == .gradient {
                ColorSwatchButton(color: $state.backgroundColor2, depth: 0.55)
            } else {
                Color.clear.frame(width: 24, height: 24)
            }
            Menu {
                Picker("Fill", selection: Binding(
                    get: { state.backgroundKind },
                    set: { kind in withAnimation(.easeInOut(duration: 0.2)) { state.backgroundKind = kind } })) {
                    ForEach(BackgroundKind.allCases) { kind in
                        Label(kind.rawValue, systemImage: kind.symbol).tag(kind)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: state.backgroundKind.symbol)
                        .font(.system(size: 13, weight: .medium))
                    Text(state.backgroundKind.rawValue)
                        .font(.subheadline)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.06)))
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Background fill, \(state.backgroundKind.rawValue)")
            Color.clear.frame(width: LabeledSlider.twoDigitValueWidth, height: 24)
        }
        .panelChrome(state)
    }
}
