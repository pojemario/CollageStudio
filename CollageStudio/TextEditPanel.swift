import SwiftUI

/// Live editor for a "Text image", shown in the panel (or sidebar) while its
/// box is selected on the collage: every change re-renders the text right
/// where it lives, so there is no separate preview. While the keyboard is up
/// only the text row stays, keeping the collage in view above it.
struct TextEditPanel: View {
    @EnvironmentObject var state: CollageState
    let imageId: UUID

    @FocusState private var typing: Bool

    /// Reads and writes the text box's style straight through the model.
    private var style: Binding<TextBoxStyle> {
        Binding(
            get: { state.textStyle(for: imageId) ?? TextBoxStyle() },
            set: { state.applyTextStyle($0, to: imageId) }
        )
    }

    var body: some View {
        VStack(spacing: 10) {
            textRow.panelChrome(state)

            if !typing {
                fontRow.panelChrome(state)
                LabeledSlider(label: "Text size",
                              value: Binding(get: { Double(style.wrappedValue.fontSize) },
                                             set: { style.wrappedValue.fontSize = CGFloat($0) }),
                              range: 30...400, step: 2, format: "%.0f", resetValue: 120)
                alignmentRow.panelChrome(state)
                colorRow.panelChrome(state)
            }
        }
        // The box was deleted or replaced by a photo: nothing left to edit.
        .onChange(of: state.textStyle(for: imageId) == nil, initial: true) { _, gone in
            if gone { state.endTextEditing() }
        }
    }

    // MARK: - Text

    private var textRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Text", text: style.text, axis: .vertical)
                .lineLimit(1...4)
                .focused($typing)
                .font(.body)
                .foregroundColor(.white)
                .tint(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.45)))

            Button {
                // First put the keyboard away, then leave text editing.
                if typing { typing = false } else { state.endTextEditing() }
            } label: {
                Label("Done", systemImage: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Font

    private var fontRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TextBoxStyle.FontChoice.allCases) { choice in
                    let isActive = style.wrappedValue.fontChoice == choice
                    Button {
                        style.wrappedValue.fontChoice = choice
                    } label: {
                        Text(choice.rawValue)
                            .font(choice.previewFont(size: 15))
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .foregroundColor(.white)
                            .background(
                                Capsule().fill(isActive ? Color.accentColor : Color.black.opacity(0.55))
                            )
                    }
                    .buttonStyle(.plain)
                }
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
            Picker("Vertical", selection: style.vAlignment) {
                Image(systemName: "arrow.up.to.line").tag(TextBoxStyle.VAlign.top)
                Image(systemName: "arrow.down.and.line.horizontal.and.arrow.up").tag(TextBoxStyle.VAlign.middle)
                Image(systemName: "arrow.down.to.line").tag(TextBoxStyle.VAlign.bottom)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    // MARK: - Colors (both support opacity, so text can float on the collage)

    private var colorRow: some View {
        HStack(spacing: 8) {
            Text("Text")
                .font(.subheadline)
            ColorSwatchButton(color: style.textColor, depth: 0.55)
            Spacer()
            Text("Background")
                .font(.subheadline)
            ColorSwatchButton(color: style.backgroundColor, depth: 0.55)
        }
        .foregroundColor(.primary)
    }
}
