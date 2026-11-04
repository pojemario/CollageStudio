import SwiftUI

/// The page's floating text, over everything else on the canvas (photos,
/// overlays, frame). A tap selects a text: dotted edges with handles show
/// and its options take the panel. Dragged it moves, pinched it scales and
/// turns; the corner handles resize it, the side handles set how wide it
/// wraps. A tap on the selected text types in it, right where it sits.
/// Exported as drawn here, without the handles.
struct FloatingTextLayer: View {
    @EnvironmentObject var state: CollageState
    /// The canvas on screen, in points.
    let canvasSize: CGSize

    // The gesture in flight, for the selected text only. Like the photos
    // and overlays, the model isn't touched until the gesture ends.
    @GestureState private var move: CGSize = .zero
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var twist: Angle = .zero
    @GestureState private var resize = Resize()
    @FocusState private var typing: UUID?

    /// A handle being dragged: the size (corners) or wrap width (sides)
    /// as a factor of what it was.
    struct Resize: Equatable {
        var scale: CGFloat = 1
        var width: CGFloat = 1
    }

    private static let space = "floatingText"
    private var onScreen: Bool { !state.isRenderingOffscreen && !state.isExporting }
    private var unit: CGFloat { FloatingText.unit(for: canvasSize) }
    /// The widest a text may wrap at, in points.
    private var maxWidth: CGFloat { canvasSize.width * 0.92 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(state.texts) { item($0) }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .coordinateSpace(name: Self.space)
        .onChange(of: state.editingTextId, initial: true) { _, id in
            guard onScreen else { return }
            typing = id
            // The starting greeting is meant to be typed over.
            if let id, let t = state.texts.first(where: { $0.id == id }),
               TextBoxStyle.greetings.contains(t.style.text) {
                Task {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    #if canImport(UIKit)
                    UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
                    #endif
                }
            }
        }
        .onChange(of: typing) { _, now in
            // The keyboard went away on its own: done typing.
            if onScreen, now == nil, state.editingTextId != nil { state.endEditingText() }
        }
    }

    // MARK: - One text

    @ViewBuilder
    private func item(_ stored: FloatingText) -> some View {
        let selected = onScreen && stored.id == state.selectedTextId
        let editing = selected && stored.id == state.editingTextId
        let t = selected ? live(stored) : stored
        let pt = t.style.fontSize * unit
        let width = boxWidth(t)

        Group {
            if editing {
                field(t, pointSize: pt, width: width)
            } else {
                FloatingTextLabel(style: t.style, pointSize: pt, width: width)
            }
        }
        .overlay {
            if selected && !editing { adorner(stored) }
        }
        .contentShape(Rectangle())
        .rotationEffect(.radians(t.rotation))
        .gesture(editing || !onScreen ? nil : moveGesture(stored))
        .simultaneousGesture(editing || !onScreen ? nil : pinchGesture(stored))
        .onTapGesture {
            guard onScreen, !editing else { return }
            state.touchFloatingText()
            if selected { state.beginEditingText(stored.id) } else { state.selectText(stored.id) }
        }
        .position(x: t.center.x * canvasSize.width, y: t.center.y * canvasSize.height)
        .allowsHitTesting(onScreen)
    }

    /// The width the text wraps at, in points: its own, or as wide as its
    /// longest line (up to the widest it may be).
    private func boxWidth(_ t: FloatingText) -> CGFloat {
        let pt = t.style.fontSize * unit
        if let w = t.width { return min(w * unit, canvasSize.width * 2) }
        let hug = FloatingTextLabel.measure(t.style, pointSize: pt, maxWidth: maxWidth).width
        return min(hug + pt * 0.08, maxWidth)
    }

    /// Typing in place: the same face, size and color, the caret in the accent.
    private func field(_ t: FloatingText, pointSize pt: CGFloat, width: CGFloat) -> some View {
        let id = t.id
        let text = Binding(
            get: { state.texts.first { $0.id == id }?.style.text ?? "" },
            set: { v in state.updateText(id) { $0.style.text = v } })
        return TextField("", text: text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(Font(t.style.fontChoice.platformFont(size: pt) as CTFont))
            .kerning(pt * t.style.letterSpacing / 100)
            .multilineTextAlignment(FloatingTextLabel.alignment(t.style))
            .foregroundStyle(t.style.textColor)
            .shadow(color: FloatingTextLabel.contrast(t.style).opacity(t.style.effect == .none ? 0 : 0.55),
                    radius: pt * 0.06)
            .tint(.accentColor)
            .focused($typing, equals: id)
            // Room for the caret and the next letter as it's typed.
            .frame(width: min(width + pt * 0.6, max(maxWidth, width)))
            .padding(FloatingTextLabel.backgroundPadding(t.style, pointSize: pt))
            .background(FloatingTextLabel.backgroundShape(t.style, pointSize: pt))
    }

    // MARK: - Handles

    /// Dotted edges (inverting what's under them, like a selected photo's)
    /// with round handles: corners resize, sides set the wrap width.
    private func adorner(_ t: FloatingText) -> some View {
        GeometryReader { g in
            let pad: CGFloat = 12
            let r = CGRect(origin: .zero, size: g.size).insetBy(dx: -pad, dy: -pad)
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.01, 5.5]))
                    .frame(width: r.width, height: r.height)
                    .offset(x: r.minX, y: r.minY)
                    .blendMode(.difference)
                    .allowsHitTesting(false)
                ForEach(Array([CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                               CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)].enumerated()),
                        id: \.offset) { i, p in
                    handle(corner: true)
                        .position(p)
                        .gesture(resizeGesture(t, corner: true))
                        .accessibilityLabel("Resize text")
                        .accessibilityIdentifier("textHandle.corner\(i)")
                }
                ForEach(Array([CGPoint(x: r.minX, y: r.midY), CGPoint(x: r.maxX, y: r.midY)].enumerated()),
                        id: \.offset) { i, p in
                    handle(corner: false)
                        .position(p)
                        .gesture(resizeGesture(t, corner: false))
                        .accessibilityLabel("Text width")
                        .accessibilityIdentifier("textHandle.side\(i)")
                }
            }
        }
    }

    private func handle(corner: Bool) -> some View {
        Group {
            if corner {
                Circle().fill(Color.white).frame(width: 14, height: 14)
            } else {
                Capsule().fill(Color.white).frame(width: 7, height: 20)
            }
        }
        .overlay {
            if corner { Circle().strokeBorder(Color.accentColor, lineWidth: 2) }
            else { Capsule().strokeBorder(Color.accentColor, lineWidth: 2) }
        }
        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        // A finger-sized target.
        .frame(width: 40, height: 40)
        .contentShape(Rectangle())
    }

    // MARK: - Gestures

    /// The text with the gesture in flight applied.
    private func live(_ t: FloatingText) -> FloatingText {
        applying(t, move: move, scale: pinch * resize.scale, width: resize.width, rotate: twist.radians)
    }

    /// `t` moved by `move` points, scaled, its wrap width scaled and turned —
    /// kept within the canvas and the sizes text may have.
    private func applying(_ t: FloatingText, move: CGSize = .zero, scale: CGFloat = 1, width: CGFloat = 1,
                          rotate: CGFloat = 0) -> FloatingText {
        var s = t
        let range = FloatingText.fontSizeRange
        s.style.fontSize = min(max(t.style.fontSize * (scale.isFinite ? scale : 1), range.lowerBound), range.upperBound)
        let k = s.style.fontSize / max(t.style.fontSize, 1)
        // A text as wide as its lines stays so when scaled; a side handle
        // gives it a width of its own.
        let maxUnits = canvasSize.width * 2 / max(unit, 0.0001)
        let w = width.isFinite ? width : 1
        if let own = t.width {
            s.width = min(max(own * k * w, 40), maxUnits)
        } else if w != 1 {
            s.width = min(max(boxWidth(t) / max(unit, 0.0001) * w, 40), maxUnits)
        }
        s.rotation = t.rotation + (rotate.isFinite ? rotate : 0)
        s.center = CGPoint(x: min(max(t.center.x + move.width / max(canvasSize.width, 1), 0), 1),
                           y: min(max(t.center.y + move.height / max(canvasSize.height, 1), 0), 1))
        return s
    }

    private func commit(_ id: UUID, _ change: (FloatingText) -> FloatingText) {
        guard let t = state.texts.first(where: { $0.id == id }) else { return }
        let new = change(t)
        state.updateText(id) { $0 = new }
    }

    private func moveGesture(_ t: FloatingText) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .updating($move) { v, s, _ in s = v.translation }
            .onChanged { _ in
                state.touchFloatingText()
                if state.selectedTextId != t.id { state.selectText(t.id) }
            }
            .onEnded { v in
                state.touchFloatingText()
                commit(t.id) { applying($0, move: v.translation) }
            }
    }

    private func pinchGesture(_ t: FloatingText) -> some Gesture {
        MagnifyGesture()
            .updating($pinch) { v, s, _ in s = v.magnification }
            .onChanged { _ in
                state.touchFloatingText()
                if state.selectedTextId != t.id { state.selectText(t.id) }
            }
            .onEnded { v in commit(t.id) { applying($0, scale: v.magnification) } }
            .simultaneously(with:
                RotateGesture()
                    .updating($twist) { v, s, _ in s = v.rotation }
                    .onEnded { v in commit(t.id) { applying($0, rotate: CGFloat(v.rotation.radians)) } })
    }

    /// A handle dragged: the size (or wrap width) follows how far the finger
    /// is from the text's center, compared with where it started.
    private func resizeGesture(_ t: FloatingText, corner: Bool) -> some Gesture {
        let c = CGPoint(x: t.center.x * canvasSize.width, y: t.center.y * canvasSize.height)
        func factor(_ v: DragGesture.Value) -> CGFloat {
            if corner {
                let d0 = hypot(v.startLocation.x - c.x, v.startLocation.y - c.y)
                let d1 = hypot(v.location.x - c.x, v.location.y - c.y)
                return d1 / max(d0, 1)
            }
            // Along the text's own width (it may be turned).
            let ax = cos(t.rotation), ay = sin(t.rotation)
            let d0 = abs((v.startLocation.x - c.x) * ax + (v.startLocation.y - c.y) * ay)
            let d1 = abs((v.location.x - c.x) * ax + (v.location.y - c.y) * ay)
            return d1 / max(d0, 1)
        }
        return DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .updating($resize) { v, s, _ in
                s = corner ? Resize(scale: factor(v)) : Resize(width: factor(v))
            }
            .onChanged { _ in state.touchFloatingText() }
            .onEnded { v in
                state.touchFloatingText()
                let f = factor(v)
                commit(t.id) { corner ? applying($0, scale: f) : applying($0, width: f) }
            }
    }
}

// MARK: - The text as drawn

/// Floating text in its look: on screen and in the export alike.
struct FloatingTextLabel: View {
    let style: TextBoxStyle
    let pointSize: CGFloat
    /// Wrap width, in points.
    let width: CGFloat

    var body: some View {
        ZStack {
            if style.effect == .outline {
                // The outline: the letters in the text's opposite, nudged
                // round in a ring, under the letters themselves.
                let r = pointSize * 0.045
                ForEach(0..<12, id: \.self) { i in
                    let a = Double(i) * .pi / 6
                    letters(Self.contrast(style))
                        .offset(x: cos(a) * r, y: sin(a) * r)
                }
            }
            letters(style.textColor)
                .shadow(color: Self.contrast(style).opacity(style.effect == .shadow ? 0.55 : 0),
                        radius: pointSize * 0.07, y: pointSize * 0.04)
        }
        .padding(Self.backgroundPadding(style, pointSize: pointSize))
        .background(Self.backgroundShape(style, pointSize: pointSize))
    }

    private func letters(_ color: Color) -> some View {
        Text(style.text.isEmpty ? " " : style.text)
            .font(Font(style.fontChoice.platformFont(size: pointSize) as CTFont))
            .kerning(pointSize * style.letterSpacing / 100)
            .multilineTextAlignment(Self.alignment(style))
            .foregroundStyle(color)
            .frame(width: width, alignment: Self.frameAlignment(style))
            .fixedSize(horizontal: false, vertical: true)
    }

    static func alignment(_ style: TextBoxStyle) -> TextAlignment {
        switch style.hAlignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    static func frameAlignment(_ style: TextBoxStyle) -> Alignment {
        switch style.hAlignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    /// Black behind light text, white behind dark.
    static func contrast(_ style: TextBoxStyle) -> Color {
        #if canImport(UIKit)
        var white: CGFloat = 0, alpha: CGFloat = 0
        UIColor(style.textColor).getWhite(&white, alpha: &alpha)
        return white > 0.5 ? .black : .white
        #else
        return .black
        #endif
    }

    private static func hasBackground(_ style: TextBoxStyle) -> Bool {
        style.backgroundColor.srgbComponents[3] > 0.01
    }

    static func backgroundPadding(_ style: TextBoxStyle, pointSize: CGFloat) -> EdgeInsets {
        guard hasBackground(style) else { return EdgeInsets() }
        let h = pointSize * 0.3, v = pointSize * 0.12
        return EdgeInsets(top: v, leading: h, bottom: v, trailing: h)
    }

    @ViewBuilder
    static func backgroundShape(_ style: TextBoxStyle, pointSize: CGFloat) -> some View {
        if hasBackground(style) {
            RoundedRectangle(cornerRadius: pointSize * 0.22, style: .continuous).fill(style.backgroundColor)
        }
    }

    /// The text's size when wrapped at `maxWidth`, in points.
    static func measure(_ style: TextBoxStyle, pointSize: CGFloat, maxWidth: CGFloat) -> CGSize {
        let font = style.fontChoice.platformFont(size: pointSize)
        let text = style.text.isEmpty ? " " : style.text
        let r = (text as NSString).boundingRect(
            with: CGSize(width: max(maxWidth, 1), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: font, .kern: pointSize * style.letterSpacing / 100], context: nil)
        return CGSize(width: ceil(r.width), height: ceil(r.height))
    }
}
