import SwiftUI

/// Modal editor for a "Text image": text content, font, size, horizontal and
/// vertical alignment, and text/background colors (both support opacity, so
/// text can float directly on the collage background). A live preview shows
/// exactly what the re-rendered image will look like.
struct TextImageEditorView: View {
    @EnvironmentObject var state: CollageState
    @Environment(\.dismiss) private var dismiss
    let imageId: UUID

    @State private var style = TextBoxStyle()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    preview
                        .frame(maxWidth: .infinity, alignment: .center)
                } header: {
                    Text("Preview")
                }

                Section {
                    TextField("Text", text: $style.text, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Text")
                }

                Section {
                    Picker("Font", selection: $style.fontChoice) {
                        ForEach(TextBoxStyle.FontChoice.allCases) { choice in
                            Text(choice.rawValue).tag(choice)
                        }
                    }
                    HStack {
                        Text("Size")
                        Slider(value: $style.fontSize, in: 40...300, step: 2)
                        Text("\(Int(style.fontSize))")
                            .font(.subheadline.monospacedDigit())
                            .foregroundColor(.secondary)
                            .frame(width: 40, alignment: .trailing)
                    }
                } header: {
                    Text("Font")
                }

                Section {
                    Picker("Horizontal", selection: $style.hAlignment) {
                        Image(systemName: "text.alignleft").tag(TextBoxStyle.HAlign.leading)
                        Image(systemName: "text.aligncenter").tag(TextBoxStyle.HAlign.center)
                        Image(systemName: "text.alignright").tag(TextBoxStyle.HAlign.trailing)
                    }
                    .pickerStyle(.segmented)
                    Picker("Vertical", selection: $style.vAlignment) {
                        Image(systemName: "arrow.up.to.line").tag(TextBoxStyle.VAlign.top)
                        Image(systemName: "arrow.down.and.line.horizontal.and.arrow.up").tag(TextBoxStyle.VAlign.middle)
                        Image(systemName: "arrow.down.to.line").tag(TextBoxStyle.VAlign.bottom)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Alignment")
                }

                Section {
                    ColorPicker("Text", selection: $style.textColor, supportsOpacity: true)
                    ColorPicker("Background", selection: $style.backgroundColor, supportsOpacity: true)
                } header: {
                    Text("Colors")
                }
            }
            .navigationTitle("Edit Text")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        state.applyTextStyle(style, to: imageId)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            if let current = state.textStyle(for: imageId) {
                style = current
            }
        }
    }

    /// Live render at preview size — same routine as the real image, over a
    /// checkerboard so transparent backgrounds read as transparent.
    private var preview: some View {
        let rendered = CollageImage.renderTextImage(style: style, side: 400)
        return CheckerboardBackground()
            .frame(width: 200, height: 200)
            .overlay(
                Group {
                    #if canImport(UIKit)
                    Image(uiImage: rendered).resizable()
                    #else
                    Image(nsImage: rendered).resizable()
                    #endif
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
            )
    }
}

/// Light gray checkerboard indicating transparency, like image editors use.
private struct CheckerboardBackground: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 10
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = CGFloat(row % 2) * cell
                while x < size.width {
                    context.fill(Path(CGRect(x: x, y: y, width: cell, height: cell)),
                                 with: .color(Color(white: 0.85)))
                    x += cell * 2
                }
                y += cell
                row += 1
            }
        }
    }
}
