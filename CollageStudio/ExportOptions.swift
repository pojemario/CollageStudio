import SwiftUI
#if canImport(UIKit)
import Photos
#endif

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

    #if canImport(UIKit)
    private static func onWhite(_ image: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: image.size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: image.size))
            image.draw(at: .zero)
        }
    }
    #endif

    func encode(_ image: PlatformImage) -> Data? {
        #if canImport(UIKit)
        switch format {
        // JPEG and HEIC have no transparency: see-through parts (a clear
        // background) would turn black, so they go on white first.
        case .jpeg: return Self.onWhite(image).jpegData(compressionQuality: 0.92)
        case .heic:
            let flat = Self.onWhite(image)
            return flat.heicData() ?? flat.jpegData(compressionQuality: 0.92)
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
    /// Pictures those pages make (wide pages make several).
    private var exportablePictures: Int {
        state.pages.filter { !$0.images.isEmpty }.reduce(0) { $0 + min(max($1.style.slides, 1), CollageState.maxSlides) }
    }

    var body: some View {
        NavigationStack {
            Form {
                if exportablePictures > exportablePages {
                    Section {
                        Label("A spread page goes out as several posts, numbered in order. Post them together and they join up when swiped.",
                              systemImage: "rectangle.split.3x1")
                            .font(.footnote)
                    }
                }
                if exportablePages > 1 {
                    Section {
                        Picker("Pages", selection: $allPages) {
                            Text(state.slides > 1 ? "This page (\(state.slides))" : "This page").tag(false)
                            Text("All \(exportablePictures) posts").tag(true)
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
            }
            // Where it goes: straight into Photos, or the share sheet
            // (Instagram, Messages, Files…). Always in view.
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button { export(to: .photos) } label: {
                        Label("Save to Photos", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button { export(to: .share) } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .controlSize(.large)
                .fontWeight(.semibold)
                // Each on one line, shrinking a little rather than wrapping.
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)
            }
        }
    }

    private func export(to destination: CollageState.ExportDestination) {
        ExportSettings.saved = settings
        let all = allPages && exportablePages > 1
        let chosen = settings
        dismiss()
        Task { await state.exportPages(allPages: all, settings: chosen, to: destination) }
    }

    private func detail(for size: ExportSettings.Size) -> String {
        let px = settings.withSize(size).pixelSize(for: state.pictureSize)
        let each = exportablePictures > 1 ? "each post " : ""
        return "\(each)\(Int(px.width)) × \(Int(px.height)) px · \(size.detail)"
    }

    /// Social feeds crop other shapes; say which canvas ratios fit.
    private var instagramHint: String? {
        switch state.ratio {
        case .square, .portrait45, .portrait34: return nil
        case .portrait916: return "9:16 fits stories and reels; feed posts usually show it cropped to 3:4."
        default: return "Feed posts fit best at 4:5, 3:4 or 1:1 (change it with the ratio button)."
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

#if canImport(UIKit)
/// Exported pictures straight into Photos, in their order (a carousel's
/// posts follow one another in the library).
enum PhotoLibrarySaver {
    enum Result { case saved(Int), denied, failed }

    static func save(_ urls: [URL]) async -> Result {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return .denied }
        do {
            // One at a time, so the order in the library is the posts' order.
            for url in urls {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: url, options: nil)
                }
            }
            return .saved(urls.count)
        } catch {
            Diagnostics.log("save to Photos failed: \(error.localizedDescription)")
            return .failed
        }
    }
}
#endif
