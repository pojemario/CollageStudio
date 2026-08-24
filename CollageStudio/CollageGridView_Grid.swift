import SwiftUI

struct CollageGridView_Grid: View {
    @EnvironmentObject var state: CollageState
    let scale: CGFloat

    var body: some View {
        GeometryReader { geo in
            let canvasSize = geo.size
            let gap = state.gap * scale
            let resolvedFrame = state.resolvedFrame()
            // Ratio-mismatch fallback: the square 1:1 frame is scaled so the
            // complete canvas fits inside it (side = longer canvas edge,
            // centered). Its overflow on the short axis is clipped off-canvas,
            // so the frame's baked-in margins only apply where its border is
            // actually visible.
            let isSquareFallback = resolvedFrame?.isSquareFallback == true
            let frameSide = max(canvasSize.width, canvasSize.height)
            let overflowX = isSquareFallback ? (frameSide - canvasSize.width) / 2 : 0
            let overflowY = isSquareFallback ? (frameSide - canvasSize.height) / 2 : 0
            // Effective margins: the frame's built-in minimums (reduced by any
            // off-canvas overflow) plus the user-adjustable extra margin.
            let base = state.frameBaseMargins
            let added = CGFloat(state.canvasMargin) * scale
            let insetL = max(0, base.left * scale - overflowX) + added
            let insetT = max(0, base.top * scale - overflowY) + added
            let insetR = max(0, base.right * scale - overflowX) + added
            let insetB = max(0, base.bottom * scale - overflowY) + added
            let contentSize = CGSize(width: max(canvasSize.width - insetL - insetR, 0),
                                     height: max(canvasSize.height - insetT - insetB, 0))
            let cols = state.layout.columns

            ZStack {
                // Empty canvas is transparent so the app background shows
                // through behind the "add images" button; once there's content
                // the user-chosen collage background applies.
                if cols.isEmpty {
                    Color.clear
                } else {
                    state.backgroundColor
                }

                if cols.isEmpty {
                    emptyState
                } else {
                    ZStack {
                        grid(canvasSize: contentSize, gap: gap, cols: cols)

                        // Interactive resize handles float above the boxes with a
                        // finger-friendly hit area, independent of the gap size.
                        // They are invisible unless hovered/dragged, so they don't
                        // affect the exported image.
                        resizeHandles(canvasSize: contentSize, gap: gap, cols: cols)
                    }
                    .frame(width: contentSize.width, height: contentSize.height)
                    // Tilt the whole collage within the canvas
                    .rotationEffect(.degrees(state.canvasRotation))
                    // Asymmetric margins shift the content block off-center
                    .offset(x: (insetL - insetR) / 2, y: (insetT - insetB) / 2)

                    // Decorative PNG frame. Exact-ratio frames cover the
                    // canvas; the square fallback is drawn undistorted at the
                    // longer canvas edge, centered, cropped by the canvas.
                    if let resolvedFrame {
                        frameOverlay(image: resolvedFrame.image,
                                     size: isSquareFallback
                                         ? CGSize(width: frameSide, height: frameSide)
                                         : canvasSize)
                    }
                }
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
        }
    }

    // MARK: - PNG frame overlay

    @ViewBuilder
    private func frameOverlay(image: PlatformImage, size: CGSize) -> some View {
        #if canImport(UIKit)
        Image(uiImage: image)
            .resizable()
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(false)
        #else
        Image(nsImage: image)
            .resizable()
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(false)
        #endif
    }

    // MARK: - Grid

    @ViewBuilder
    private func grid(canvasSize: CGSize, gap: CGFloat, cols: [[ColumnItem]]) -> some View {
        let widths = columnWidths(canvasSize: canvasSize, gap: gap, cols: cols)

        HStack(spacing: gap) {
            ForEach(Array(cols.enumerated()), id: \.offset) { ci, col in
                columnView(col: col, ci: ci, canvasSize: canvasSize, gap: gap, colWidth: widths[ci])
            }
        }
        // Center the collage block so the reserved edge gaps are
        // distributed evenly on all sides (horizontally and vertically).
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .center)
        .animation(state.isResizing ? nil : .interactiveSpring(), value: state.layout.colGrows)
        .animation(state.isResizing ? nil : .interactiveSpring(), value: state.layout.boxGrows)
    }

    @ViewBuilder
    private func columnView(col: [ColumnItem], ci: Int, canvasSize: CGSize, gap: CGFloat, colWidth: CGFloat) -> some View {
        if col.isEmpty {
            // Column without images: one transparent placeholder box spanning
            // the full column height
            EmptyBoxView(scale: scale, columnIndex: ci)
                .frame(width: colWidth)
                .frame(height: max(canvasSize.height - gap * 2, 0))
        } else {
            let heights = boxHeights(col: col, ci: ci, canvasSize: canvasSize, gap: gap)

            VStack(spacing: gap) {
                ForEach(Array(col.enumerated()), id: \.element.id) { bi, item in
                    ImageBoxView(imageId: item.imageId, scale: scale)
                        .frame(maxWidth: .infinity)
                        .frame(height: heights[bi])
                }
            }
            .frame(width: colWidth)
        }
    }

    // MARK: - Layout math

    private func columnWidths(canvasSize: CGSize, gap: CGFloat, cols: [[ColumnItem]]) -> [CGFloat] {
        let totalGrow = state.layout.colGrows.reduce(0, +)
        let availW = canvasSize.width - gap * CGFloat(cols.count + 1)
        return (0..<cols.count).map { ci in
            let g = ci < state.layout.colGrows.count ? state.layout.colGrows[ci] : 1.0
            return totalGrow > 0 ? (g / totalGrow) * availW : 0
        }
    }

    private func boxHeights(col: [ColumnItem], ci: Int, canvasSize: CGSize, gap: CGFloat) -> [CGFloat] {
        let grows = ci < state.layout.boxGrows.count ? state.layout.boxGrows[ci] : []
        let totalGrow = grows.reduce(0, +)
        let availH = canvasSize.height - gap * CGFloat(col.count + 1)
        return (0..<col.count).map { bi in
            let g = bi < grows.count ? grows[bi] : 1.0
            return totalGrow > 0 ? (g / totalGrow) * availH : 0
        }
    }

    // MARK: - Resize handles

    @ViewBuilder
    private func resizeHandles(canvasSize: CGSize, gap: CGFloat, cols: [[ColumnItem]]) -> some View {
        let widths = columnWidths(canvasSize: canvasSize, gap: gap, cols: cols)
        let availW = canvasSize.width - gap * CGFloat(cols.count + 1)
        // Hug the actual gap: a couple of points of bleed at most, so
        // pinch/pan touches near a box edge always reach the image. (28pt
        // strips used to bleed ~14pt onto the images and swallowed pinch
        // fingers — boxes sandwiched between strips went gesture-dead.)
        let hitThickness = max(gap, 14)

        ZStack {
            // Vertical handles between columns
            ForEach(1..<max(cols.count, 1), id: \.self) { ci in
                let x = gap + widths.prefix(ci).reduce(0, +) + gap * CGFloat(ci - 1) + gap / 2
                ColumnResizeHandle(ciA: ci - 1, ciB: ci, availW: availW)
                    .frame(width: hitThickness, height: max(canvasSize.height - gap * 2, 0))
                    .position(x: x, y: canvasSize.height / 2)
            }

            // Horizontal handles between boxes within each column
            ForEach(Array(cols.enumerated()), id: \.offset) { ci, col in
                let heights = boxHeights(col: col, ci: ci, canvasSize: canvasSize, gap: gap)
                let availH = canvasSize.height - gap * CGFloat(col.count + 1)
                let colCenterX = gap + widths.prefix(ci).reduce(0, +) + gap * CGFloat(ci) + widths[ci] / 2

                ForEach(1..<max(col.count, 1), id: \.self) { bi in
                    let y = gap + heights.prefix(bi).reduce(0, +) + gap * CGFloat(bi - 1) + gap / 2
                    BoxResizeHandle(ci: ci, biA: bi - 1, biB: bi, availH: availH)
                        .frame(width: max(widths[ci], 0), height: hitThickness)
                        .position(x: colCenterX, y: y)
                }
            }
        }
    }

    // MARK: - Empty state

    // The empty canvas itself stays blank — the big "add images" button is
    // overlaid by CanvasContainerView.
    private var emptyState: some View {
        Color.clear
    }
}

// MARK: - Column resize handle (between columns)

private struct ColumnResizeHandle: View {
    @EnvironmentObject var state: CollageState
    let ciA: Int
    let ciB: Int
    let availW: CGFloat

    @GestureState private var isDragging = false
    @State private var isHovering = false

    var body: some View {
        ZStack {
            Color.clear
            if isHovering || isDragging {
                Capsule()
                    .fill(Color.white.opacity(isDragging ? 0.9 : 0.6))
                    .frame(width: isDragging ? 5 : 3, height: isDragging ? 40 : 32)
                    .shadow(color: .black.opacity(0.25), radius: 2)
            }
        }
        .contentShape(Rectangle())
        .cursor(.resizeLeftRight)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isDragging)
        .gesture(
            // Drag in the stable canvas coordinate space — the handle itself
            // moves while resizing, so a local-space translation would feed
            // back into itself and jitter.
            DragGesture(minimumDistance: 0, coordinateSpace: .named("collageCanvas"))
                .updating($isDragging) { _, dragState, _ in dragState = true }
                .onChanged { value in
                    if !state.isResizing { state.beginResize() }
                    state.updateResizeCols(ciA: ciA, ciB: ciB,
                                           totalDeltaFraction: value.translation.width / max(availW, 1))
                }
                .onEnded { _ in state.endResize() }
        )
    }
}

// MARK: - Box resize handle (between boxes in a column)

private struct BoxResizeHandle: View {
    @EnvironmentObject var state: CollageState
    let ci: Int
    let biA: Int
    let biB: Int
    let availH: CGFloat

    @GestureState private var isDragging = false
    @State private var isHovering = false

    var body: some View {
        ZStack {
            Color.clear
            if isHovering || isDragging {
                Capsule()
                    .fill(Color.white.opacity(isDragging ? 0.9 : 0.6))
                    .frame(width: isDragging ? 40 : 32, height: isDragging ? 5 : 3)
                    .shadow(color: .black.opacity(0.25), radius: 2)
            }
        }
        .contentShape(Rectangle())
        .cursor(.resizeUpDown)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isDragging)
        .gesture(
            // Stable canvas coordinate space — see ColumnResizeHandle.
            DragGesture(minimumDistance: 0, coordinateSpace: .named("collageCanvas"))
                .updating($isDragging) { _, dragState, _ in dragState = true }
                .onChanged { value in
                    if !state.isResizing { state.beginResize() }
                    state.updateResizeBoxes(colIndex: ci, biA: biA, biB: biB,
                                            totalDeltaFraction: value.translation.height / max(availH, 1))
                }
                .onEnded { _ in state.endResize() }
        )
    }
}
