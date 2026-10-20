import SwiftUI

/// How a collage is exported: size and file format, remembered between exports.
struct ExportSettings: Equatable {
    enum Size: String, CaseIterable, Identifiable {
        case standard = "Standard"
        case instagram = "Instagram"
        case print = "Print"
        var id: String { rawValue }

        /// Shown in the picker (the raw value is what's remembered).
        var title: String {
            switch self {
            case .standard: return "Standard"
            case .instagram: return "Social"
            case .print: return "Print"
            }
        }

        var detail: String {
            switch self {
            case .standard: return "Sharp on any screen"
            case .instagram: return "1080 px wide, for social feeds"
            case .print: return "For prints up to ~35 cm"
            }
        }
    }

    enum Format: String, CaseIterable, Identifiable {
        case jpeg = "JPEG"
        case heic = "HEIC"
        case png = "PNG"
        var id: String { rawValue }
        var fileExtension: String { rawValue.lowercased() == "jpeg" ? "jpg" : rawValue.lowercased() }
        var detail: String {
            switch self {
            case .jpeg: return "Works everywhere"
            case .heic: return "Half the size, Apple devices"
            case .png: return "Lossless, largest files"
            }
        }
    }

    var size: Size = .standard
    var format: Format = .jpeg

    /// Render scale for a canvas (in points) to come out at this size.
    func scale(for canvas: CGSize) -> CGFloat {
        switch size {
        case .standard: return 2
        case .instagram: return 1080 / max(canvas.width, 1)
        case .print: return 4096 / max(canvas.width, canvas.height, 1)
        }
    }

    func pixelSize(for canvas: CGSize) -> CGSize {
        let k = scale(for: canvas)
        return CGSize(width: (canvas.width * k).rounded(), height: (canvas.height * k).rounded())
    }

    private static let key = "exportSettings"

    static var saved: ExportSettings {
        get {
            let d = UserDefaults.standard.dictionary(forKey: key) ?? [:]
            var s = ExportSettings()
            if let v = d["size"] as? String, let size = Size(rawValue: v) { s.size = size }
            if let v = d["format"] as? String, let format = Format(rawValue: v) { s.format = format }
            return s
        }
        set { UserDefaults.standard.set(["size": newValue.size.rawValue, "format": newValue.format.rawValue], forKey: key) }
    }

    func encode(_ image: PlatformImage) -> Data? {
        #if canImport(UIKit)
        switch format {
        case .jpeg: return image.jpegData(compressionQuality: 0.92)
        case .heic: return image.heicData() ?? image.jpegData(compressionQuality: 0.92)
        case .png: return image.pngData()
        }
        #else
        return ProjectStore.png(image)
        #endif
    }
}

/// The share button's sheet: which pages, what size, which format.
struct ExportOptionsView: View {
    @EnvironmentObject var state: CollageState
    @Environment(\.dismiss) private var dismiss
    @State private var settings = ExportSettings.saved
    @State private var allPages = true

    private var exportablePages: Int { state.pages.filter { !$0.images.isEmpty }.count }

    var body: some View {
        NavigationStack {
            Form {
                if exportablePages > 1 {
                    Section {
                        Picker("Pages", selection: $allPages) {
                            Text("This page").tag(false)
                            Text("All \(exportablePages) pages").tag(true)
                        }
                        .pickerStyle(.segmented)
                    } footer: {
                        if allPages {
                            Text("Numbered in order and all the same size — ready to post as a carousel.")
                        }
                    }
                }
                // Size and format as drop-down menus, so the sheet stays
                // short; the chosen option's details show under each.
                Section {
                    Picker("Size", selection: $settings.size) {
                        ForEach(ExportSettings.Size.allCases) { size in
                            Text(size.title).tag(size)
                        }
                    }
                    .pickerStyle(.menu)
                    Picker("Format", selection: $settings.format) {
                        ForEach(ExportSettings.Format.allCases) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .pickerStyle(.menu)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(settings.size.title): \(detail(for: settings.size))")
                        Text("\(settings.format.rawValue): \(settings.format.detail)")
                        if settings.size == .instagram, let hint = instagramHint {
                            Label(hint, systemImage: "lightbulb")
                                .padding(.top, 4)
                        }
                    }
                }
            }
            .navigationTitle("Export Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export") {
                        ExportSettings.saved = settings
                        let all = allPages && exportablePages > 1
                        let chosen = settings
                        dismiss()
                        Task { await state.exportPages(allPages: all, settings: chosen) }
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func detail(for size: ExportSettings.Size) -> String {
        let px = settings.withSize(size).pixelSize(for: state.canvasSize)
        return "\(Int(px.width)) × \(Int(px.height)) px · \(size.detail)"
    }

    /// Social feeds crop other shapes; say which canvas ratios fit.
    private var instagramHint: String? {
        switch state.ratio {
        case .square, .portrait45: return nil
        case .portrait916: return "9:16 fits stories and reels; feed posts usually show it cropped to 4:5."
        default: return "Feed posts fit best at 4:5 or 1:1 (change it with the ratio button)."
        }
    }
}

private extension ExportSettings {
    func withSize(_ size: Size) -> ExportSettings {
        var s = self
        s.size = size
        return s
    }
}
