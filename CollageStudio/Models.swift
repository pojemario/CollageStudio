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

    /// Swaps in a new picture, regenerating the working copies.
    mutating func setImage(_ newImage: PlatformImage) {
        image = newImage
        proxy = newImage.downsampled(longEdge: Self.proxyLongEdge)
        thumb = newImage.downsampled(longEdge: Self.thumbLongEdge)
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

    var id: String { baseName }
    var displayName: String { baseName }

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
