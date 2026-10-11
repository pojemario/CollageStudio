import SwiftUI

/// Live editor for a "Text image", shown in the panel (or sidebar) while its
/// box is selected on the collage: every change re-renders the text right
/// where it lives, so there is no separate preview. It opens with every
/// option showing; while the keyboard is up only the text row stays,
/// keeping the collage in view above it.
struct TextEditPanel: View {
    @EnvironmentObject var state: CollageState
    let imageId: UUID

    @FocusState private var typing: Bool

    /// Reads and writes the text box's style straight through the model.
    private var style: Binding<TextBoxStyle> {
        Binding(
            get: { state.textStyle(for: imageId) ?? TextBoxStyle() },
            set: {
                state.applyTextStyle($0, to: imageId)
                // The next new text box starts from this look.
                TextBoxStyle.lastUsed = $0
            }
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
        // Another text box opened in the same panel: start without the keyboard.
        .onChange(of: imageId) { _, _ in typing = false }
        // The starting text is meant to be replaced: select it all as typing begins.
        .onChange(of: typing) { _, now in
            guard now, style.wrappedValue.text == TextBoxStyle().text else { return }
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
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 38, height: 38)
                        .appButtonBackground(prominent: false)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hide keyboard")
                .transition(.opacity)
            }
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
                            .foregroundColor(isActive ? .white : .primary)
                            .appButtonBackground(prominent: isActive)
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
