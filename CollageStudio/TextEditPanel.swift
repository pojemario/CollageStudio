import SwiftUI

/// Live editor for a "Text image", shown in the panel (or sidebar) while its
/// box is selected on the collage: every change re-renders the text right
/// where it lives, so there is no separate preview. A new text box opens
/// ready to type; an existing one with every option showing. While the
/// keyboard is up only the text row stays, keeping the collage in view.
///
/// Floating text uses it too: typed in place on the collage, so its panel
/// has the text's tools (Edit, Reset, Remove) instead of the text row.
struct TextEditPanel: View {
    @EnvironmentObject var state: CollageState
    let target: Target

    enum Target: Equatable {
        /// A text box in the layout (an image id).
        case box(UUID)
        /// Floating text on the page.
        case floating(UUID)
    }

    init(imageId: UUID) { target = .box(imageId) }
    init(textId: UUID) { target = .floating(textId) }

    private var imageId: UUID {
        switch target {
        case .box(let id), .floating(let id): return id
        }
    }
    private var isFloating: Bool { if case .floating = target { return true } else { return false } }
    /// Floating text being typed in on the collage: only its tools show.
    private var typingInPlace: Bool { isFloating && state.editingTextId == imageId }

    @FocusState private var typing: Bool

    /// The options in three tabs under the text: the face and its size, the
    /// look (style, colors), and where the text sits in its box. The last
    /// one chosen comes back for the next text box.
    enum Page: String, CaseIterable { case font = "Font", style = "Look", align = "Align" }
    private static var lastPage: Page = .font
    @State private var page: Page = TextEditPanel.lastPage

    /// Reads and writes the text box's style straight through the model.
    private var style: Binding<TextBoxStyle> {
        let id = imageId
        if isFloating {
            return Binding(
                get: { state.texts.first { $0.id == id }?.style ?? TextBoxStyle.lastFloating },
                set: { new in
                    state.updateText(id) { $0.style = new }
                    // The next new text starts from this look.
                    TextBoxStyle.lastFloating = new
                }
            )
        }
        return Binding(
            get: { state.textStyle(for: id) ?? TextBoxStyle() },
            set: {
                state.applyTextStyle($0, to: id)
                // The next new text box starts from this look.
                TextBoxStyle.lastUsed = $0
            }
        )
    }

    var body: some View {
        VStack(spacing: 10) {
            if isFloating {
                floatingTools.panelChrome(state)
            } else {
                textRow.panelChrome(state)
            }

            if !typing && !typingInPlace {
                Picker("Text options", selection: $page) {
                    ForEach(Page.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .panelChrome(state)
                .onChange(of: page) { _, now in Self.lastPage = now }
                switch page {
                case .font:
                    fontRow.panelChrome(state)
                    LabeledSlider(label: "Size",
                                  value: Binding(get: { Double(style.wrappedValue.fontSize) },
                                                 set: { style.wrappedValue.fontSize = CGFloat($0) }),
                                  range: isFloating ? Double(FloatingText.fontSizeRange.lowerBound)...Double(FloatingText.fontSizeRange.upperBound) : 30...400,
                                  step: 2, format: "%.0f",
                                  resetValue: isFloating ? Double(FloatingText.defaultFontSize) : 120)
                    LabeledSlider(label: "Spacing",
                                  value: Binding(get: { Double(style.wrappedValue.letterSpacing) },
                                                 set: { style.wrappedValue.letterSpacing = CGFloat($0) }),
                                  range: -10...60, step: 1, format: "%.0f", resetValue: 0)
                case .style:
                    Picker("Style", selection: style.effect) {
                        ForEach(TextBoxStyle.Effect.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .panelChrome(state)
                    colorRow.panelChrome(state)
                case .align:
                    alignmentRow.panelChrome(state)
                }
            }
        }
        // The box was deleted or replaced by a photo: nothing left to edit.
        .onChange(of: state.textStyle(for: imageId) == nil, initial: true) { _, gone in
            if gone && !isFloating { state.endTextEditing() }
        }
        // A new text box goes straight to typing (once the panel has risen);
        // an existing one opens with every option showing.
        .task(id: imageId) {
            guard !isFloating, state.focusTextOnOpen else {
                typing = false
                return
            }
            state.focusTextOnOpen = false
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            typing = true
        }
        // The starting text is meant to be replaced: select it all as typing begins.
        .onChange(of: typing) { _, now in
            guard now, TextBoxStyle.greetings.contains(style.wrappedValue.text) else { return }
            Task {
                try? await Task.sleep(nanoseconds: 150_000_000)
                selectAllInFocusedField()
            }
        }
    }

    private func selectAllInFocusedField() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
        #else
        NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
        #endif
    }

    // MARK: - Text

    private var textRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Text", text: style.text, axis: .vertical)
                .lineLimit(1...4)
                .focused($typing)
                .font(.body)
                .foregroundColor(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .appButtonBackground(prominent: false)

            // Puts the keyboard away, bringing the other options back.
            if typing {
                Button { typing = false } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 38, height: 38)
                        .appButtonBackground(prominent: false)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Text options")
                .transition(.opacity)
            }
        }
    }

    // MARK: - Floating text tools

    /// Edit (types on the collage) or Done while typing, Reset (place, size and
    /// turn back to how new text starts; the words and look stay), Remove.
    private var floatingTools: some View {
        HStack(spacing: 8) {
            if typingInPlace {
                toolButton("Done", sf: "checkmark", prominent: true) { state.endEditingText() }
            } else {
                toolButton("Edit", sf: "pencil") { state.beginEditingText(imageId) }
            }
            toolButton("Reset", sf: "arrow.counterclockwise") { state.resetText(imageId) }
            Spacer(minLength: 0)
            toolButton("Remove", sf: "trash") { state.removeText(imageId) }
        }
    }

    private func toolButton(_ title: String, sf: String, prominent: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: sf)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(prominent ? .white : .primary)
                .padding(.horizontal, 14)
                .frame(height: 40)
                .appButtonBackground(prominent: prominent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title == "Edit" ? "Edit text" : title == "Remove" ? "Remove text" : title)
    }

    // MARK: - Font

    /// Two rows that scroll sideways, each packed from the left with even
    /// gaps, every button the same height: white with the name in black in
    /// its own face; the chosen one white on the accent.
    private var fontRow: some View {
        let all = TextBoxStyle.FontChoice.allCases
        let half = (all.count + 1) / 2
        return SelectionScroller(selection: style.wrappedValue.fontChoice) {
            VStack(alignment: .leading, spacing: 2) {
                fontButtons(Array(all.prefix(half)))
                fontButtons(Array(all.dropFirst(half)))
            }
            .padding(.vertical, 1)
        }
    }

    private func fontButtons(_ choices: [TextBoxStyle.FontChoice]) -> some View {
        let shape = RoundedRectangle(cornerRadius: ButtonStyleGuide.cornerRadius, style: .continuous)
        return HStack(spacing: 2) {
            ForEach(choices) { choice in
                let isActive = style.wrappedValue.fontChoice == choice
                Button {
                    style.wrappedValue.fontChoice = choice
                } label: {
                    Text(choice.rawValue)
                        .font(choice.previewFont(size: 20))
                        .lineLimit(1)
                        .foregroundColor(isActive ? .white : .black)
                        .padding(.horizontal, 14)
                        .frame(height: 40)
                        .background(shape.fill(isActive ? Color.accentColor : Color.white))
                        // Tall faces (Zapfino) stay inside the button.
                        .clipShape(shape)
                        .overlay(shape.strokeBorder(Color.black.opacity(isActive ? 0 : 0.12), lineWidth: 1))
                        .contentShape(shape)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isActive ? .isSelected : [])
                .id(choice)
            }
        }
    }

    // MARK: - Alignment

    private var alignmentRow: some View {
        HStack(spacing: 10) {
            Picker("Horizontal", selection: style.hAlignment) {
                Image(systemName: "text.alignleft").tag(TextBoxStyle.HAlign.leading)
                Image(systemName: "text.aligncenter").tag(TextBoxStyle.HAlign.center)
                Image(systemName: "text.alignright").tag(TextBoxStyle.HAlign.trailing)
            }
            // (Floating text has no box to sit higher or lower in.)
            if !isFloating {
                Picker("Vertical", selection: style.vAlignment) {
                    Image(systemName: "arrow.up.to.line").tag(TextBoxStyle.VAlign.top)
                    Image(systemName: "arrow.down.and.line.horizontal.and.arrow.up").tag(TextBoxStyle.VAlign.middle)
                    Image(systemName: "arrow.down.to.line").tag(TextBoxStyle.VAlign.bottom)
                }
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    // MARK: - Colors (both support opacity, so text can float on the collage)

    private var colorRow: some View {
        HStack(spacing: 8) {
            Text("Text")
                .font(.panelLabel)
            ColorSwatchButton(color: style.textColor, depth: 0.55)
            Spacer()
            Text("Background")
                .font(.panelLabel)
            ColorSwatchButton(color: style.backgroundColor,
                              presetTitle: "Transparent", presetColor: { .clear },
                              depth: 0.55, accessibilityTitle: "Background color")
        }
        .foregroundColor(.primary)
    }
}
