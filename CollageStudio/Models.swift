import SwiftUI

// MARK: - Platform Image

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
extension NSImage {
    var cgImage: CGImage? {
        var rect = CGRect(origin: .zero, size: self.size)
        return self.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
#endif

extension PlatformImage {
    /// Cross-platform asset-catalog lookup; nil when the asset doesn't exist.
    static func named(_ name: String) -> PlatformImage? {
        #if canImport(UIKit)
        return UIImage(named: name)
        #else
        return NSImage(named: name)
        #endif
    }
}

// MARK: - Image downsampling

extension PlatformImage {
    /// Returns a copy scaled down so its long edge is at most `longEdge`.
    /// Returns self if the image is already small enough.
    func downsampled(longEdge target: CGFloat) -> PlatformImage {
        let maxDim = max(size.width, size.height)
        guard maxDim > target, maxDim > 0 else { return self }
        let factor = target / maxDim
        let newSize = CGSize(width: floor(size.width * factor),
                             height: floor(size.height * factor))
        #if canImport(UIKit)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
        #else
        let scaled = NSImage(size: newSize)
        scaled.lockFocus()
        draw(in: CGRect(origin: .zero, size: newSize),
             from: CGRect(origin: .zero, size: size),
             operation: .copy, fraction: 1)
        scaled.unlockFocus()
        return scaled
        #endif
    }
}

// MARK: - Text box style

/// Everything needed to (re)render a "Text image": a text box that lives in
/// the collage as a normal rendered image and can be re-edited at any time.
struct TextBoxStyle: Equatable {
    var text: String = "Your text"
    var fontChoice: FontChoice = .classic
    /// Point size on a bitmap whose long edge is 1200 px.
    var fontSize: CGFloat = 120
    var hAlignment: HAlign = .center
    var vAlignment: VAlign = .middle
    var textColor: Color = .black
    var backgroundColor: Color = .white

    enum HAlign: String, CaseIterable, Identifiable {
        case leading, center, trailing
        var id: String { rawValue }
    }

    enum VAlign: String, CaseIterable, Identifiable {
        case top, middle, bottom
        var id: String { rawValue }
    }

    /// Fonts offered for text boxes, grouped sans → thin → serif → script
    /// and handwriting. All are built into iOS.
    enum FontChoice: String, CaseIterable, Identifiable {
        // Sans
        case classic = "Classic"
        case rounded = "Rounded"
        case futura = "Futura"
        // Thin sans
        case thin = "Thin"
        case hairline = "Hairline"
        case avenir = "Avenir"
        case gill = "Gill"
        // Serif
        case serif = "Serif"
        case didot = "Didot"
        case typewriter = "Typewriter"
        // Script & handwriting
        case script = "Script"
        case savoye = "Savoye"
        case zapfino = "Zapfino"
        case handwritten = "Handwritten"
        case note = "Note"
        case chalk = "Chalk"
        case marker = "Marker"

        var id: String { rawValue }

        /// PostScript name of the face; nil for the system font variants.
        var postScriptName: String? {
            switch self {
            case .classic, .rounded, .thin: return nil
            case .futura:      return "Futura-Medium"
            case .hairline:    return "HelveticaNeue-UltraLight"
            case .avenir:      return "AvenirNext-UltraLight"
            case .gill:        return "GillSans-Light"
            case .serif:       return "Georgia"
            case .didot:       return "Didot"
            case .typewriter:  return "AmericanTypewriter"
            case .script:      return "SnellRoundhand-Bold"
            case .savoye:      return "SavoyeLetPlain"
            case .zapfino:     return "Zapfino"
            case .handwritten: return "BradleyHandITCTT-Bold"
            case .note:        return "Noteworthy-Light"
            case .chalk:       return "Chalkduster"
            case .marker:      return "MarkerFelt-Wide"
            }
        }

        /// The same face for SwiftUI labels (font chips).
        func previewFont(size: CGFloat) -> Font {
            switch self {
            case .classic: return .system(size: size, weight: .semibold)
            case .rounded: return .system(size: size, weight: .semibold, design: .rounded)
            case .thin:    return .system(size: size, weight: .thin)
            default:       return .custom(postScriptName ?? "", size: size)
            }
        }

        /// The face for rendering, at a given size.
        func platformFont(size: CGFloat) -> PlatformFont {
            switch self {
            case .classic:
                return .systemFont(ofSize: size, weight: .semibold)
            case .thin:
                return .systemFont(ofSize: size, weight: .thin)
            case .rounded:
                let base = PlatformFont.systemFont(ofSize: size, weight: .semibold)
                #if canImport(UIKit)
                if let d = base.fontDescriptor.withDesign(.rounded) { return UIFont(descriptor: d, size: size) }
                #else
                if let d = base.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: d, size: size) { return f }
                #endif
                return base
            default:
                return PlatformFont(name: postScriptName ?? "", size: size) ?? .systemFont(ofSize: size)
            }
        }
    }
}

#if canImport(UIKit)
typealias PlatformFont = UIFont
#else
typealias PlatformFont = NSFont
#endif

extension CollageImage {

    /// Bitmap size for a text image living in a box of the given size: same
    /// aspect ratio, 1200 px long edge — so the text block always fills its
    /// box exactly instead of being cropped to it.
    static func textRenderSize(forBox box: CGSize) -> CGSize {
        guard box.width > 1, box.height > 1 else { return CGSize(width: 1200, height: 1200) }
        let k = 1200 / max(box.width, box.height)
        return CGSize(width: max((box.width * k).rounded(), 60), height: max((box.height * k).rounded(), 60))
    }

    /// Renders a text box bitmap. Same routine for the initial add and every
    /// edit, so what you see is exactly what exports.
    static func renderTextImage(style: TextBoxStyle,
                                size: CGSize = CGSize(width: 1200, height: 1200)) -> PlatformImage {
        let side = max(size.width, size.height)
        let inset = side * 0.06
        let maxRect = CGRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height - inset * 2)
        // The font size is defined on a 1200 px long edge.
        let scaledFontSize = style.fontSize * (side / 1200)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        switch style.hAlignment {
        case .leading:  paragraph.alignment = .left
        case .center:   paragraph.alignment = .center
        case .trailing: paragraph.alignment = .right
        }

        #if canImport(UIKit)
        let font = style.fontChoice.platformFont(size: scaledFontSize)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor(style.textColor),
            .paragraphStyle: paragraph,
        ]

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor(style.backgroundColor).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            let bounding = (style.text as NSString).boundingRect(
                with: CGSize(width: maxRect.width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin], attributes: attrs, context: nil)
            let textHeight = min(bounding.height.rounded(.up), maxRect.height)
            let y: CGFloat
            switch style.vAlignment {
            case .top:    y = maxRect.minY
            case .middle: y = maxRect.minY + (maxRect.height - textHeight) / 2
            case .bottom: y = maxRect.maxY - textHeight
            }
            (style.text as NSString).draw(
                with: CGRect(x: maxRect.minX, y: y, width: maxRect.width, height: textHeight),
                options: [.usesLineFragmentOrigin], attributes: attrs, context: nil)
        }
        #else
        let font = style.fontChoice.platformFont(size: scaledFontSize)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(style.textColor),
            .paragraphStyle: paragraph,
        ]

        let img = NSImage(size: size)
        img.lockFocus()
        NSColor(style.backgroundColor).setFill()
        CGRect(origin: .zero, size: size).fill()
        let bounding = (style.text as NSString).boundingRect(
            with: CGSize(width: maxRect.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin], attributes: attrs)
        let textHeight = min(bounding.height.rounded(.up), maxRect.height)
        let y: CGFloat
        switch style.vAlignment {
        case .top:    y = maxRect.minY
        case .middle: y = maxRect.minY + (maxRect.height - textHeight) / 2
        case .bottom: y = maxRect.maxY - textHeight
        }
        (style.text as NSString).draw(
            with: CGRect(x: maxRect.minX, y: y, width: maxRect.width, height: textHeight),
            options: [.usesLineFragmentOrigin], attributes: attrs)
        img.unlockFocus()
        return img
        #endif
    }
}

// MARK: - CollageImage

struct CollageImage: Identifiable, Equatable {
    /// Long-edge caps for the derived working copies.
    static let proxyLongEdge: CGFloat = 800
    static let thumbLongEdge: CGFloat = 240

    let id: UUID
    /// Full-resolution original — only drawn during export.
    var image: PlatformImage
    /// Downscaled copy used for all on-canvas rendering and gestures.
    var proxy: PlatformImage
    /// Tiny copy for the thumbnail strips.
    var thumb: PlatformImage
    /// True for the transparent "empty image" placeholder — it flows through
    /// layout and gestures like any image, but its pixels are fully
    /// transparent so the collage shows an intentional empty space.
    var isPlaceholder: Bool = false
    /// Non-nil for "Text images": the style this image was rendered from,
    /// kept so the text stays editable (tap the box).
    var textStyle: TextBoxStyle? = nil
    var isText: Bool { textStyle != nil }
    /// Bumped after every committed pinch. The box view uses it as its
    /// identity, forcing SwiftUI to rebuild the gesture recognizers — repeated
    /// two-finger gestures can otherwise corrupt a view's recognizers and
    /// leave the box permanently deaf to touch.
    var gestureEpoch: Int = 0
    var panOffset: CGSize = .zero
    var zoom: CGFloat = 1.0
    /// Rotation of the image within its box, in radians.
    var rotation: CGFloat = 0
    var lastBoxSize: CGSize = .zero

    static func == (lhs: CollageImage, rhs: CollageImage) -> Bool {
        // Compare the image reference too, so views refresh when an image
        // is replaced in place (same id, new picture).
        lhs.id == rhs.id && lhs.image === rhs.image
    }

    init(image: PlatformImage) {
        self.id = UUID()
        self.image = image
        self.proxy = image.downsampled(longEdge: Self.proxyLongEdge)
        self.thumb = image.downsampled(longEdge: Self.thumbLongEdge)
    }

    /// Swaps in a new picture, regenerating the working copies. Replacing a
    /// placeholder or text box with a real photo makes it a normal image
    /// again (applyTextStyle restores textStyle after its re-render).
    mutating func setImage(_ newImage: PlatformImage) {
        image = newImage
        proxy = newImage.downsampled(longEdge: Self.proxyLongEdge)
        thumb = newImage.downsampled(longEdge: Self.thumbLongEdge)
        isPlaceholder = false
        textStyle = nil
    }

    /// A "Text image": a rendered text box that behaves like any other image.
    static func textImage(style: TextBoxStyle) -> CollageImage {
        var img = CollageImage(image: renderTextImage(style: style))
        img.textStyle = style
        return img
    }

    /// An "empty image": a fully transparent square placeholder that users
    /// place to leave deliberate gaps in a collage.
    static func emptyPlaceholder(side: CGFloat = 300) -> CollageImage {
        let size = CGSize(width: side, height: side)
        #if canImport(UIKit)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        // Rendering nothing yields a fully transparent bitmap.
        let img = UIGraphicsImageRenderer(size: size, format: format).image { _ in }
        #else
        let img = NSImage(size: size)
        #endif
        var collage = CollageImage(image: img)
        collage.isPlaceholder = true
        return collage
    }

    /// All layout math (aspect-fill, pan clamping) uses the original's
    /// dimensions; the proxy has the same aspect ratio and is stretched into
    /// the same frame, so geometry is identical in preview and export.
    var naturalSize: CGSize {
        image.size
    }
}

// MARK: - Collage page

/// Per-page visual settings (the Layout tab). Ratio, canvas margin and the
/// decorative frame remain global.
/// Defaults match what the Reset button applies, so a fresh collage starts
/// with the same plain look.
struct PageStyle: Equatable {
    var numCols: Int = 2
    var gap: Double = 10
    var cornerRadius: Double = 20
    var backgroundColor: Color = .white
    var borderColor: Color = .white
    var borderThickness: Double = 0
    var borderStyle: BorderStyle = .solid
    var borderPlacement: BorderPlacement = .center
    var linkBorderToBackground: Bool = true
}

/// One page of the collage document: its own images, ordering, layout and
/// visual style.
struct CollagePage: Identifiable {
    let id = UUID()
    var images: [CollageImage] = []
    var order: [UUID] = []
    var layout: CollageLayout = CollageLayout()
    var style: PageStyle = PageStyle()
}

// MARK: - Canvas frame set

/// A bundled decorative frame. Each set lists its per-ratio asset variants;
/// asset names encode metadata, e.g. "Medium_m26562656_r4x5":
///  - "Medium" — display name
///  - "m26562656" — minimum content margins: left/top/right/bottom,
///    two digits each, in canvas pixels (may differ per ratio variant)
///  - "r4x5" — the canvas ratio this PNG is drawn for
struct CanvasFrameSet: Identifiable, Equatable {
    let baseName: String
    /// Full asset names of all bundled variants of this frame.
    let variantAssets: [String]
    /// Picker label when it should differ from the (unique) base name.
    var label: String? = nil

    var id: String { baseName }
    var displayName: String { label ?? baseName }

    /// Full asset name for a ratio suffix like "1x1" or "9x16".
    func assetName(ratioSuffix: String) -> String? {
        variantAssets.first { $0.hasSuffix("_r\(ratioSuffix)") }
    }

    /// Minimum content margins encoded in a variant's asset name
    /// (canvas pixels). Zero margins when the name has no m-component.
    static func margins(fromAssetName name: String) -> (left: CGFloat, top: CGFloat, right: CGFloat, bottom: CGFloat) {
        for comp in name.split(separator: "_") {
            guard comp.first == "m" else { continue }
            let digits = comp.dropFirst().prefix(8)
            guard digits.count == 8, digits.allSatisfy(\.isNumber),
                  let l = Int(digits.prefix(2)),
                  let t = Int(digits.dropFirst(2).prefix(2)),
                  let r = Int(digits.dropFirst(4).prefix(2)),
                  let b = Int(digits.dropFirst(6).prefix(2)) else { continue }
            return (CGFloat(l), CGFloat(t), CGFloat(r), CGFloat(b))
        }
        return (0, 0, 0, 0)
    }
}

// MARK: - Frame pack

/// A themed collection of frames drawn for ONE canvas format and used as is:
/// no per-ratio variants and no square fallback, so every imperfection lands
/// exactly where it was drawn. The format is part of the title so users can
/// tell which pack fits their collage.
///
/// Assets live in Assets.xcassets/FramePacks/<pack>/ and follow the
/// CanvasFrameSet naming scheme, prefixed with a pack id to stay unique,
/// e.g. "Analog916_Notch_m45454545_r9x16".
struct FramePack: Identifiable {
    let name: String
    let ratio: CanvasRatio
    let frames: [CanvasFrameSet]

    var id: String { "\(name)_\(ratio.rawValue)" }
    var title: String { "\(name) (\(ratio.rawValue))" }

    /// Builds a pack from asset names shaped "<prefix>_<Label>_m…_r…".
    init(name: String, ratio: CanvasRatio, assets: [String]) {
        self.name = name
        self.ratio = ratio
        self.frames = assets.map { asset in
            let parts = asset.split(separator: "_")
            return CanvasFrameSet(baseName: parts.prefix(2).joined(separator: "_"),
                                  variantAssets: [asset],
                                  label: parts.count > 1 ? String(parts[1]) : asset)
        }
    }
}

// MARK: - Overlays

/// What an overlay simulates — decides how it is composited.
enum OverlayKind: String {
    case dust = "Dust & Scratches"
    case leak = "Light Leaks"

    /// Light leaks add light (screen), so dark areas of the picture pick up
    /// their glow; dust and scratches simply sit on top.
    var blendMode: BlendMode {
        self == .leak ? .screen : .normal
    }
}

/// A bundled set of overlay textures of one kind. Unlike frames, overlays
/// carry no fixed geometry — they fill whatever canvas they land on and can
/// be moved, scaled and rotated freely — so packs aren't tied to a format.
///
/// Assets live in Assets.xcassets/Overlays/<pack>/, named "<prefix>_<Label>".
struct OverlayPack: Identifiable {
    let name: String
    let kind: OverlayKind
    let assets: [String]

    var id: String { name }

    static func label(forAsset asset: String) -> String {
        asset.split(separator: "_").last.map(String.init) ?? asset
    }
}

/// One overlay layer stacked on the collage. Layers draw in list order,
/// either under or over the decorative frame.
struct OverlayLayer: Identifiable, Equatable {
    let id = UUID()
    let asset: String
    let kind: OverlayKind
    /// Percent, 0...100.
    var opacity: Double = 100
    var aboveFrame: Bool = false
    // Placement, adjusted by finger on the canvas: scale and rotation about
    // the center of the canvas-filling texture, then an offset in canvas pixels.
    var scale: CGFloat = 1
    var rotation: CGFloat = 0       // radians
    var offset: CGSize = .zero

    /// Drawn long edge limits, in canvas pixels — the failsafe that keeps a
    /// texture from being pinched into a speck or blown up past recognition.
    static let longEdgeRange: ClosedRange<CGFloat> = 200...4000

    var label: String { OverlayPack.label(forAsset: asset) }

    /// This layer with a gesture applied, forced back into sane territory:
    /// non-finite values are discarded, the drawn size stays within
    /// `longEdgeRange`, the rotation is normalized, and the center can't
    /// leave the canvas — so an overlay can never vanish from the screen.
    /// `translation` is in canvas pixels.
    func applying(scaleBy: CGFloat = 1, rotateBy: CGFloat = 0, translation: CGSize = .zero,
                  canvasSize: CGSize) -> OverlayLayer {
        func finite(_ v: CGFloat, or fallback: CGFloat) -> CGFloat { v.isFinite ? v : fallback }
        var layer = self

        let longEdge = max(canvasSize.width, canvasSize.height, 1)
        let zoom = finite(scale, or: 1) * max(finite(scaleBy, or: 1), 0.0001)
        layer.scale = min(max(zoom, Self.longEdgeRange.lowerBound / longEdge),
                          Self.longEdgeRange.upperBound / longEdge)

        let angle = finite(rotation, or: 0) + finite(rotateBy, or: 0)
        layer.rotation = atan2(sin(angle), cos(angle))

        let x = finite(offset.width, or: 0) + finite(translation.width, or: 0)
        let y = finite(offset.height, or: 0) + finite(translation.height, or: 0)
        layer.offset = CGSize(width: min(max(x, -canvasSize.width / 2), canvasSize.width / 2),
                              height: min(max(y, -canvasSize.height / 2), canvasSize.height / 2))
        return layer
    }
}

// MARK: - Effects

/// Whole-collage looks, each dialed in by its own intensity (0...100).
/// They act on the pictures and background — overlays and the frame sit on
/// top, untouched.
enum CollageEffect: String, CaseIterable, Identifiable {
    case fade = "Fade"              // + lifted blacks, softer contrast; − more contrast
    case halation = "Halation"      // red-orange bleed around highlights
    case glow = "Glow"              // soft bloom
    case blackWhite = "B&W"
    case vignette = "Vignette"
    case grain = "Grain"

    var id: String { rawValue }
    var title: String { rawValue }

    /// Fade runs both ways (negative = punchier contrast).
    var range: ClosedRange<Double> { self == .fade ? -100...100 : 0...100 }
}

// MARK: - Canvas Ratio

enum CanvasRatio: String, CaseIterable, Identifiable {
    // Declaration order defines the ratio grid order (3 per row):
    // 1:1, 4:5, 4:3 / 9:16, 5:4, 3:2 / 16:9, 2:3, Custom
    case square      = "1:1"
    case portrait45  = "4:5"
    case landscape43 = "4:3"
    case portrait916 = "9:16"
    case landscape54 = "5:4"
    case landscape32 = "3:2"
    case landscape169 = "16:9"
    case portrait23  = "2:3"
    case custom      = "Custom"

    var id: String { rawValue }

    func canvasSize(base: CGFloat = 1024) -> CGSize {
        switch self {
        case .square:       return CGSize(width: base, height: base)
        case .portrait45:   return CGSize(width: base * 4/5, height: base)
        case .landscape54:  return CGSize(width: base, height: base * 4/5)
        case .landscape32:  return CGSize(width: base, height: base * 2/3)
        case .landscape43:  return CGSize(width: base, height: base * 3/4)
        case .portrait916:  return CGSize(width: base * 9/16, height: base)
        case .landscape169: return CGSize(width: base, height: base * 9/16)
        case .portrait23:   return CGSize(width: base * 2/3, height: base)
        case .custom:       return CGSize(width: base, height: base)
        }
    }
}

// MARK: - Border Style

enum BorderStyle: String, CaseIterable, Identifiable {
    case solid     = "Solid"
    case dashed    = "Dashed"
    case dotted    = "Dotted"
    case dashDot   = "Dash-Dot"
    case triangles = "Triangles"
    case slashes   = "Slashes"
    case crosses   = "Crosses"

    var id: String { rawValue }

    /// Styles drawn by stamping small shapes along the border path instead
    /// of stroking a dash pattern.
    var usesStamps: Bool {
        switch self {
        case .triangles, .slashes, .crosses: return true
        default: return false
        }
    }

    /// Stroke style for the given effective line width. Dash lengths are
    /// proportional to the line width, so the pattern scales consistently
    /// between the on-screen preview and the full-resolution export.
    func strokeStyle(lineWidth: CGFloat) -> StrokeStyle {
        switch self {
        case .solid:
            return StrokeStyle(lineWidth: lineWidth)
        case .dashed:
            return StrokeStyle(lineWidth: lineWidth, lineCap: .butt,
                               dash: [lineWidth * 3, lineWidth * 2])
        case .dotted:
            // Zero-length segments with round caps render as circular dots
            return StrokeStyle(lineWidth: lineWidth, lineCap: .round,
                               dash: [0.001, lineWidth * 2])
        case .dashDot:
            return StrokeStyle(lineWidth: lineWidth, lineCap: .round,
                               dash: [lineWidth * 3, lineWidth * 2, 0.001, lineWidth * 2])
        case .triangles, .slashes, .crosses:
            // Stamp styles are rendered by StampedBorderView, not a stroke
            return StrokeStyle(lineWidth: lineWidth)
        }
    }
}

// MARK: - Border Placement

enum BorderPlacement: String, CaseIterable, Identifiable {
    case inner  = "Inner"
    case center = "Center"
    case outer  = "Outer"

    var id: String { rawValue }

    /// Inset applied to the stroked rectangle so the line falls fully inside
    /// the box edge, centered on it, or fully outside of it.
    func inset(lineWidth: CGFloat) -> CGFloat {
        switch self {
        case .inner:  return lineWidth / 2
        case .center: return 0
        case .outer:  return -lineWidth / 2
        }
    }
}

// MARK: - Custom Unit

enum CustomUnit: String, CaseIterable, Identifiable {
    case px = "px"
    case mm = "mm"

    var id: String { rawValue }

    // 200 DPI: 1 mm = 200 / 25.4 px
    static let mmToPx: CGFloat = 200.0 / 25.4

    func toPx(_ value: CGFloat) -> CGFloat {
        switch self {
        case .px: return value
        case .mm: return value * Self.mmToPx
        }
    }

    func fromPx(_ value: CGFloat) -> CGFloat {
        switch self {
        case .px: return value
        case .mm: return value / Self.mmToPx
        }
    }
}

// MARK: - Column Layout Item

struct ColumnItem: Identifiable {
    var id: UUID { imageId }
    let imageId: UUID
    let aspectRatio: CGFloat  // h / w
}

// MARK: - Collage Layout

struct CollageLayout {
    var columns: [[ColumnItem]] = []
    var colGrows: [CGFloat] = []
    var boxGrows: [[CGFloat]] = []

    mutating func rebuild(images: [CollageImage], order: [UUID], numCols: Int) {
        let n = order.count
        guard n > 0 else { columns = []; return }

        // Never more columns than images.
        let cols = max(1, min(numCols, n))
        var cols2D: [[ColumnItem]] = Array(repeating: [], count: cols)

        // Round-robin assignment for balance
        for (i, id) in order.enumerated() {
            guard let img = images.first(where: { $0.id == id }) else { continue }
            let s = img.naturalSize
            let ar = s.height / max(s.width, 1)
            let col = i % cols
            cols2D[col].append(ColumnItem(imageId: id, aspectRatio: ar))
        }

        columns = cols2D

        // Reset colGrows if column count changed
        if colGrows.count != cols {
            colGrows = Array(repeating: 1.0, count: cols)
        }

        // Set boxGrows to equal shares for each image in a column
        var newBoxGrows: [[CGFloat]] = []
        for col in cols2D {
            if col.count > 0 {
                newBoxGrows.append(Array(repeating: 1.0 / CGFloat(col.count), count: col.count))
            } else {
                newBoxGrows.append([])
            }
        }
        boxGrows = newBoxGrows
    }

    mutating func resetGrows() {
        colGrows = []
        boxGrows = []
    }

    // Compute pixel rects for every image at a given canvas size
    func rects(canvasSize: CGSize, gap: CGFloat) -> [UUID: CGRect] {
        var result: [UUID: CGRect] = [:]
        let cols = columns.count
        guard cols > 0, cols <= colGrows.count else { return result }

        let totalColGrow = colGrows.prefix(cols).reduce(0, +)
        guard totalColGrow > 0 else { return result }
        let availW = canvasSize.width - gap * CGFloat(cols + 1)

        var xOffset = gap
        for (ci, col) in columns.enumerated() {
            guard ci < colGrows.count, ci < boxGrows.count else { continue }
            let colW = (colGrows[ci] / totalColGrow) * availW
            let grows = boxGrows[ci]
            let totalBoxGrow = grows.reduce(0, +)
            guard totalBoxGrow > 0 else { continue }
            let availH = canvasSize.height - gap * CGFloat(col.count + 1)

            var yOffset = gap
            for (bi, item) in col.enumerated() {
                let g = bi < grows.count ? grows[bi] : 1
                let boxH = (g / totalBoxGrow) * availH
                result[item.imageId] = CGRect(x: xOffset, y: yOffset, width: colW, height: boxH)
                yOffset += boxH + gap
            }
            xOffset += colW + gap
        }
        return result
    }
}
