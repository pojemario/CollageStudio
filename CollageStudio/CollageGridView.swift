import SwiftUI

struct CollageGridView: View {
    @EnvironmentObject var state: CollageState
    let scale: CGFloat

    var body: some View {
        GeometryReader { geo in
            let canvasSize = geo.size
            let gap = state.gap * scale
            let cols = state.layout.columns
            guard !cols.isEmpty else {
                return AnyView(emptyState)
            }

            return AnyView(
                HStack(spacing: 0) {
                    ForEach(Array(cols.enumerated()), id: \.offset) { ci, col in
                        // Vertical splitter before each column except first
                        if ci > 0 {
                            VerticalSplitterView(ciA: ci - 1, ciB: ci, canvasSize: canvasSize)
                                .frame(width: gap)
                        }

                        // Column
                        columnView(col: col, ci: ci, canvasSize: canvasSize, gap: gap)
                    }
                }
                .padding(gap)
                .background(state.backgroundColor)
                .frame(width: canvasSize.width, height: canvasSize.height)
            )
        }
    }

    // MARK: - Column

    func columnView(col: [ColumnItem], ci: Int, canvasSize: CGSize, gap: CGFloat) -> some View {
        return GeometryReader { colGeo in
            VStack(spacing: 0) {
                ForEach(Array(col.enumerated()), id: \.element.id) { bi, item in
                    // Horizontal splitter before each box except first
                    if bi > 0 {
                        HorizontalSplitterView(ci: ci, biA: bi - 1, biB: bi, canvasSize: colGeo.size)
                            .frame(height: gap)
                    }

                    // Image box
                    imageBox(id: item.imageId, ci: ci, bi: bi)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Image box with flex-grow

    func imageBox(id: UUID, ci: Int, bi: Int) -> some View {
        let grow = (ci < state.layout.boxGrows.count && bi < state.layout.boxGrows[ci].count)
            ? state.layout.boxGrows[ci][bi]
            : 1.0

        return ImageBoxView(imageId: id, scale: scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // SwiftUI doesn't have flex-grow, so we use layoutPriority + frame
            .layoutPriority(grow)
    }

    // MARK: - Empty state

    var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44))
                .foregroundColor(.secondary.opacity(0.4))
            Text("Add images to start")
                .foregroundColor(.secondary.opacity(0.5))
                .font(.callout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Horizontal Splitter (between boxes in a column)

struct HorizontalSplitterView: View {
    @EnvironmentObject var state: CollageState
    let ci: Int
    let biA: Int
    let biB: Int
    let canvasSize: CGSize

    @GestureState private var isDragging = false
    @GestureState private var dragAmount: CGFloat = 0
    @State private var isHovering = false

    var body: some View {
        ZStack {
            state.backgroundColor
            if isHovering || isDragging || dragAmount != 0 {
                Capsule()
                    .fill(isDragging ? Color.white.opacity(0.9) : Color.white.opacity(0.6))
                    .frame(width: isDragging ? 40 : 32, height: isDragging ? 5 : 3)
                    .animation(.spring(), value: dragAmount)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .cursor(.resizeUpDown)
        .onHover { isHovering = $0 }
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($dragAmount) { value, state, _ in
                    state = value.translation.height
                }
                .updating($isDragging) { _, state, _ in
                    state = true
                }
                .onChanged { value in
                    if !state.isResizing {
                        state.beginResize()
                    }
                    let fraction = value.translation.height / max(canvasSize.height, 1)
                    state.updateResizeBoxes(colIndex: ci, biA: biA, biB: biB, totalDeltaFraction: fraction)
                }
                .onEnded { _ in
                    state.endResize()
                }
        )
    }
}

// MARK: - Vertical Splitter (between columns)

struct VerticalSplitterView: View {
    @EnvironmentObject var state: CollageState
    let ciA: Int
    let ciB: Int
    let canvasSize: CGSize

    @GestureState private var dragAmount: CGFloat = 0
    @GestureState private var isDragging = false
    @State private var isHovering = false

    var body: some View {
        ZStack {
            state.backgroundColor
            if isHovering || isDragging || dragAmount != 0 {
                Capsule()
                    .fill(isDragging ? Color.white.opacity(0.9) : Color.white.opacity(0.6))
                    .frame(width: isDragging ? 5 : 3, height: isDragging ? 40 : 32)
                    .animation(.spring(), value: dragAmount)
            }
        }
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .cursor(.resizeLeftRight)
        .onHover { isHovering = $0 }
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($dragAmount) { value, state, _ in
                    state = value.translation.width
                }
                .updating($isDragging) { _, state, _ in
                    state = true
                }
                .onChanged { value in
                    if !state.isResizing {
                        state.beginResize()
                    }
                    let fraction = value.translation.width / max(canvasSize.width, 1)
                    state.updateResizeCols(ciA: ciA, ciB: ciB, totalDeltaFraction: fraction)
                }
                .onEnded { _ in
                    state.endResize()
                }
        )
    }
}

// MARK: - Cursor modifier (macOS only)

extension View {
    @ViewBuilder
    func cursor(_ cursor: CustomCursor) -> some View {
        #if os(macOS)
        self.onHover { inside in
            if inside {
                switch cursor {
                case .resizeUpDown:    NSCursor.resizeUpDown.push()
                case .resizeLeftRight: NSCursor.resizeLeftRight.push()
                }
            } else {
                NSCursor.pop()
            }
        }
        #else
        self
        #endif
    }
}

enum CustomCursor { case resizeUpDown, resizeLeftRight }
