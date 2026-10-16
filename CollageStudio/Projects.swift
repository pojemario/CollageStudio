import SwiftUI
import Combine

// MARK: - Stored forms

extension PageStyle: Codable {
    private enum CodingKeys: String, CodingKey {
        case numCols, isRows, gap, cornerRadius, backgroundColor, borderColor, borderThickness
        case borderStyle, borderPlacement, linkBorderToBackground, backgroundKind, backgroundColor2
    }

    /// Missing or unknown entries keep their defaults, so older files load.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        numCols = max(1, try c.decodeIfPresent(Int.self, forKey: .numCols) ?? numCols)
        isRows = try c.decodeIfPresent(Bool.self, forKey: .isRows) ?? isRows
        gap = try c.decodeIfPresent(Double.self, forKey: .gap) ?? gap
        cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? cornerRadius
        if let v = try c.decodeIfPresent([Double].self, forKey: .backgroundColor), let col = Color(srgbComponents: v) { backgroundColor = col }
        if let v = try c.decodeIfPresent([Double].self, forKey: .borderColor), let col = Color(srgbComponents: v) { borderColor = col }
        borderThickness = try c.decodeIfPresent(Double.self, forKey: .borderThickness) ?? borderThickness
        if let v = try c.decodeIfPresent(String.self, forKey: .borderStyle), let s = BorderStyle(rawValue: v) { borderStyle = s }
        if let v = try c.decodeIfPresent(String.self, forKey: .borderPlacement), let p = BorderPlacement(rawValue: v) { borderPlacement = p }
        linkBorderToBackground = try c.decodeIfPresent(Bool.self, forKey: .linkBorderToBackground) ?? linkBorderToBackground
        if let v = try c.decodeIfPresent(String.self, forKey: .backgroundKind), let k = BackgroundKind(rawValue: v) { backgroundKind = k }
        if let v = try c.decodeIfPresent([Double].self, forKey: .backgroundColor2), let col = Color(srgbComponents: v) { backgroundColor2 = col }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(numCols, forKey: .numCols)
        try c.encode(isRows, forKey: .isRows)
        try c.encode(gap, forKey: .gap)
        try c.encode(cornerRadius, forKey: .cornerRadius)
        try c.encode(backgroundColor.srgbComponents, forKey: .backgroundColor)
        try c.encode(borderColor.srgbComponents, forKey: .borderColor)
        try c.encode(borderThickness, forKey: .borderThickness)
        try c.encode(borderStyle.rawValue, forKey: .borderStyle)
        try c.encode(borderPlacement.rawValue, forKey: .borderPlacement)
        try c.encode(linkBorderToBackground, forKey: .linkBorderToBackground)
        try c.encode(backgroundKind.rawValue, forKey: .backgroundKind)
        try c.encode(backgroundColor2.srgbComponents, forKey: .backgroundColor2)
    }
}

extension TextBoxStyle {
    private static let lastUsedKey = "lastTextStyle"
    /// Set once the remembered look has dropped the old white background
    /// (from before transparent became the default).
    private static let transparentKey = "lastTextStyleTransparentDefault"

    /// The look of the text box edited last (font, size, alignment, colors),
    /// for new text boxes to start from — with fresh starting text.
    static var lastUsed: TextBoxStyle {
        get {
            guard let data = UserDefaults.standard.data(forKey: lastUsedKey),
                  var style = try? JSONDecoder().decode(TextBoxStyle.self, from: data) else { return TextBoxStyle() }
            style.text = TextBoxStyle().text
            if !UserDefaults.standard.bool(forKey: transparentKey) {
                style.backgroundColor = .clear
                UserDefaults.standard.set(true, forKey: transparentKey)
                UserDefaults.standard.set(try? JSONEncoder().encode(style), forKey: lastUsedKey)
            }
            return style
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: lastUsedKey) }
    }
}

extension TextBoxStyle: Codable {
    private enum CodingKeys: String, CodingKey {
        case text, fontChoice, fontSize, hAlignment, vAlignment, textColor, backgroundColor
    }

    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? text
        if let v = try c.decodeIfPresent(String.self, forKey: .fontChoice), let f = FontChoice(rawValue: v) { fontChoice = f }
        fontSize = try c.decodeIfPresent(CGFloat.self, forKey: .fontSize) ?? fontSize
        if let v = try c.decodeIfPresent(String.self, forKey: .hAlignment), let a = HAlign(rawValue: v) { hAlignment = a }
        if let v = try c.decodeIfPresent(String.self, forKey: .vAlignment), let a = VAlign(rawValue: v) { vAlignment = a }
        if let v = try c.decodeIfPresent([Double].self, forKey: .textColor), let col = Color(srgbComponents: v) { textColor = col }
        if let v = try c.decodeIfPresent([Double].self, forKey: .backgroundColor), let col = Color(srgbComponents: v) { backgroundColor = col }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(text, forKey: .text)
        try c.encode(fontChoice.rawValue, forKey: .fontChoice)
        try c.encode(fontSize, forKey: .fontSize)
        try c.encode(hAlignment.rawValue, forKey: .hAlignment)
        try c.encode(vAlignment.rawValue, forKey: .vAlignment)
        try c.encode(textColor.srgbComponents, forKey: .textColor)
        try c.encode(backgroundColor.srgbComponents, forKey: .backgroundColor)
    }
}

extension ColorFilter {
    /// "none", "brownie", … or "lut:Group/Name".
    var storageKey: String {
        switch self {
        case .none: return "none"
        case .amber: return "amber"
        case .tealSplit: return "tealSplit"
        case .heritage: return "heritage"
        case .brownie: return "brownie"
        case .melancholy: return "melancholy"
        case .classicNegative: return "classicNegative"
        case .classicNegative2: return "classicNegative2"
        case .portra400: return "portra400"
        case .lut(let key): return "lut:" + key
        }
    }

    init(storageKey key: String) {
        switch key {
        case "amber": self = .amber
        case "tealSplit": self = .tealSplit
        case "heritage": self = .heritage
        case "brownie": self = .brownie
        case "melancholy": self = .melancholy
        case "classicNegative": self = .classicNegative
        case "classicNegative2": self = .classicNegative2
        case "portra400": self = .portra400
        default: self = key.hasPrefix("lut:") ? .lut(String(key.dropFirst(4))) : .none
        }
    }
}

extension HSLAdjustments {
    var storage: [String: [Double]] {
        Dictionary(uniqueKeysWithValues: shifts.map { ($0.key.rawValue, [$0.value.hue, $0.value.saturation, $0.value.luminance]) })
    }

    init(storage: [String: [Double]]) {
        self.init()
        for (k, v) in storage where v.count == 3 {
            if let band = HSLBand(rawValue: k) { self[band] = HSLShift(hue: v[0], saturation: v[1], luminance: v[2]) }
        }
    }
}

extension CameraCalibration {
    var storage: [Double] {
        [shadowsTint, redHue, redSaturation, greenHue, greenSaturation, blueHue, blueSaturation]
    }

    init(storage v: [Double]) {
        self.init()
        guard v.count == 7 else { return }
        shadowsTint = v[0]; redHue = v[1]; redSaturation = v[2]
        greenHue = v[3]; greenSaturation = v[4]; blueHue = v[5]; blueSaturation = v[6]
    }
}

extension Dictionary where Key == CollageEffect, Value == Double {
    var storage: [String: Double] { Dictionary<String, Double>(uniqueKeysWithValues: map { ($0.key.rawValue, $0.value) }) }
}

func effectsFromStorage(_ d: [String: Double]) -> [CollageEffect: Double] {
    var out: [CollageEffect: Double] = [:]
    for (k, v) in d { if let e = CollageEffect(rawValue: k) { out[e] = v } }
    return out
}

/// One saved collage, as written to project.json. Photos live next to it
/// as image files; text boxes and empty slots are re-made from their data.
struct ProjectFile: Codable {
    /// 2: Fade runs ±50 (was ±100) for the same look.
    var version = 2
    var id: UUID
    var name: String?
    var created: Date
    var modified: Date
    var currentPageIndex: Int
    var pages: [Page]
    var ratio: String
    var canvasWidth: Double
    var canvasHeight: Double
    var customWidth: String
    var customHeight: String
    var customUnit: String
    // The page on screen's look, at the top level too: files from before
    // per-page looks had only these, and older app versions still read them.
    var canvasMargin: Double
    var canvasRotation: Double
    var frame: String?
    var overlays: [Overlay]
    var effects: [String: Double]
    var hsl: [String: [Double]]
    var calibration: [Double]
    var filter: String
    var filterStrength: Double

    struct Page: Codable {
        var images: [Image]
        var order: [UUID]
        var columns: [[UUID]]
        var colGrows: [Double]
        var boxGrows: [[Double]]
        var style: PageStyle
        /// Missing in files from before per-page looks.
        var look: Look?
    }

    /// A page's margin, rotation, frame, overlays, edits and filter.
    struct Look: Codable {
        var canvasMargin: Double
        var canvasRotation: Double
        var frame: String?
        var overlays: [Overlay]
        var effects: [String: Double]
        var hsl: [String: [Double]]
        var calibration: [Double]
        var filter: String
        var filterStrength: Double
    }

    /// The top-level look (older files: the whole collage's).
    var collageLook: Look {
        Look(canvasMargin: canvasMargin, canvasRotation: canvasRotation, frame: frame, overlays: overlays,
             effects: effects, hsl: hsl, calibration: calibration, filter: filter, filterStrength: filterStrength)
    }

    struct Image: Codable {
        var id: UUID
        /// Image file name for photos; nil for text boxes and empty slots.
        var file: String?
        var isPlaceholder: Bool
        var textStyle: TextBoxStyle?
        var protrusion: Int?
        var protrusionEffect: String
        var protrusionObjects: [Int]?
        var pan: [Double]
        var zoom: Double
        var rotation: Double
        var focus: [Double]?
        var framedByUser: Bool?
    }

    struct Overlay: Codable {
        var asset: String
        var kind: String
        var opacity: Double
        var blur: Double
        var aboveFrame: Bool
        var scale: Double
        var rotation: Double
        var offset: [Double]
    }

    var imageCount: Int { pages.reduce(0) { $0 + $1.images.count } }
}

extension PageLook {
    var file: ProjectFile.Look {
        ProjectFile.Look(
            canvasMargin: canvasMargin, canvasRotation: canvasRotation, frame: canvasFrame?.baseName,
            overlays: overlayLayers.map {
                ProjectFile.Overlay(asset: $0.asset, kind: $0.kind.rawValue, opacity: $0.opacity, blur: $0.blur,
                                    aboveFrame: $0.aboveFrame, scale: Double($0.scale), rotation: Double($0.rotation),
                                    offset: [Double($0.offset.width), Double($0.offset.height)])
            },
            effects: effects.storage, hsl: hsl.storage, calibration: calibration.storage,
            filter: colorFilter.storageKey, filterStrength: filterStrength)
    }

    @MainActor
    init(file f: ProjectFile.Look) {
        let frames = CollageState.availableFrames + CollageState.framePacks.flatMap(\.frames)
        self.init(
            canvasMargin: f.canvasMargin, canvasRotation: f.canvasRotation,
            canvasFrame: f.frame.flatMap { name in frames.first { $0.baseName == name } },
            overlayLayers: f.overlays.compactMap { o in
                guard let kind = OverlayKind(rawValue: o.kind) else { return nil }
                var layer = OverlayLayer(asset: o.asset, kind: kind)
                layer.opacity = o.opacity
                layer.blur = o.blur
                layer.aboveFrame = o.aboveFrame
                layer.scale = CGFloat(o.scale)
                layer.rotation = CGFloat(o.rotation)
                if o.offset.count == 2 { layer.offset = CGSize(width: o.offset[0], height: o.offset[1]) }
                return layer
            },
            effects: effectsFromStorage(f.effects), hsl: HSLAdjustments(storage: f.hsl),
            calibration: CameraCalibration(storage: f.calibration),
            colorFilter: ColorFilter(storageKey: f.filter), filterStrength: f.filterStrength)
    }
}

/// A saved collage in the Collages list.
struct ProjectSummary: Identifiable, Equatable {
    let id: UUID
    var name: String
    var modified: Date
    var imageCount: Int
    var pageCount: Int
    var thumbURL: URL
}

// MARK: - Store

/// Saved collages on disk: Application Support/Projects/<id>/ holds
/// project.json, thumb.jpg and images/.
@MainActor
final class ProjectStore: ObservableObject {
    @Published private(set) var summaries: [ProjectSummary] = []
    /// File writes run one after another, off the main thread.
    private let io = DispatchQueue(label: "CollageStudio.projects", qos: .utility)

    nonisolated static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Projects", isDirectory: true)
    }
    nonisolated static func folder(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    nonisolated static func imagesFolder(_ id: UUID) -> URL { folder(id).appendingPathComponent("images", isDirectory: true) }
    nonisolated static func jsonURL(_ id: UUID) -> URL { folder(id).appendingPathComponent("project.json") }
    nonisolated static func thumbURL(_ id: UUID) -> URL { folder(id).appendingPathComponent("thumb.jpg") }

    static func defaultName(created: Date) -> String {
        "Collage " + created.formatted(.dateTime.day().month(.abbreviated).hour().minute())
    }

    init() { refresh() }

    /// Re-reads the list (newest first). Collages with no pictures are left
    /// out (and cleaned up).
    func refresh() {
        let fm = FileManager.default
        let folders = (try? fm.contentsOfDirectory(at: Self.root, includingPropertiesForKeys: nil)) ?? []
        var list: [ProjectSummary] = []
        for folder in folders {
            guard let id = UUID(uuidString: folder.lastPathComponent),
                  let file = Self.readFile(id) else { continue }
            guard file.imageCount > 0 else { continue }
            list.append(ProjectSummary(id: id, name: file.name ?? Self.defaultName(created: file.created),
                                       modified: file.modified, imageCount: file.imageCount,
                                       pageCount: file.pages.count, thumbURL: Self.thumbURL(id)))
        }
        summaries = list.sorted { $0.modified > $1.modified }
    }

    nonisolated static func readFile(_ id: UUID) -> ProjectFile? {
        guard let data = try? Data(contentsOf: jsonURL(id)) else { return nil }
        return try? JSONDecoder().decode(ProjectFile.self, from: data)
    }

    /// Writes a collage: new photo files first, then the thumbnail and the
    /// JSON (atomically), then drops photo files it no longer uses.
    func save(_ file: ProjectFile, newImages: [(PlatformImage, String)], thumbnail: PlatformImage?,
              completion: @escaping () -> Void) {
        let id = file.id
        let keep = Set(file.pages.flatMap { $0.images.compactMap(\.file) })
        io.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: Self.imagesFolder(id), withIntermediateDirectories: true)
            for (image, name) in newImages {
                let url = Self.imagesFolder(id).appendingPathComponent(name)
                if !fm.fileExists(atPath: url.path), let data = Self.encode(image, name: name) {
                    try? data.write(to: url, options: .atomic)
                }
            }
            if let thumbnail, let data = Self.jpeg(thumbnail, quality: 0.8) {
                try? data.write(to: Self.thumbURL(id), options: .atomic)
            }
            if let data = try? JSONEncoder().encode(file) {
                try? data.write(to: Self.jsonURL(id), options: .atomic)
            }
            let present = (try? fm.contentsOfDirectory(atPath: Self.imagesFolder(id).path)) ?? []
            for name in present where !keep.contains(name) {
                try? fm.removeItem(at: Self.imagesFolder(id).appendingPathComponent(name))
            }
            DispatchQueue.main.async(execute: completion)
        }
    }

    /// Waits for pending writes (e.g. before opening another collage).
    func flush() { io.sync {} }

    func delete(_ id: UUID) {
        io.sync { try? FileManager.default.removeItem(at: Self.folder(id)) }
        refresh()
    }

    func rename(_ id: UUID, to name: String) {
        guard var file = Self.readFile(id) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        file.name = trimmed.isEmpty ? nil : trimmed
        if let data = try? JSONEncoder().encode(file) {
            io.sync { try? data.write(to: Self.jsonURL(id), options: .atomic) }
        }
        refresh()
    }

    /// A copy under a new id, named "… copy".
    func duplicate(_ id: UUID) {
        guard var file = Self.readFile(id) else { return }
        let newId = UUID()
        io.sync {
            try? FileManager.default.copyItem(at: Self.folder(id), to: Self.folder(newId))
            file.id = newId
            file.name = (file.name ?? Self.defaultName(created: file.created)) + " copy"
            file.created = Date()
            file.modified = Date()
            if let data = try? JSONEncoder().encode(file) {
                try? data.write(to: Self.jsonURL(newId), options: .atomic)
            }
        }
        refresh()
    }

    nonisolated private static func encode(_ image: PlatformImage, name: String) -> Data? {
        name.hasSuffix(".png") ? png(image) : jpeg(image, quality: 0.92)
    }

    nonisolated static func jpeg(_ image: PlatformImage, quality: CGFloat) -> Data? {
        #if canImport(UIKit)
        return image.jpegData(compressionQuality: quality)
        #else
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
        #endif
    }

    nonisolated static func png(_ image: PlatformImage) -> Data? {
        #if canImport(UIKit)
        return image.pngData()
        #else
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
        #endif
    }

    /// Photos with transparency keep it (PNG); everything else is JPEG.
    nonisolated static func fileExtension(for image: PlatformImage) -> String {
        guard let alpha = image.cgImage?.alphaInfo else { return "jpg" }
        switch alpha {
        case .first, .last, .premultipliedFirst, .premultipliedLast: return "png"
        default: return "jpg"
        }
    }
}

// MARK: - Saving and opening collages

extension CollageState {
    private static let lastProjectKey = "lastProjectId"

    /// Saves shortly after edits settle.
    func scheduleAutosave() {
        guard !isRestoringProject else { return }
        autosaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveProjectNow() }
        autosaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    /// Writes the open collage now (if there's anything to keep).
    func saveProjectNow() {
        autosaveWork?.cancel()
        autosaveWork = nil
        guard !isRestoringProject else { return }
        let onDisk = FileManager.default.fileExists(atPath: ProjectStore.jsonURL(currentProjectId).path)
        // An empty new collage isn't worth a file; an emptied one is
        // written (empty) so it doesn't come back with its old pictures.
        guard hasAnyImages || onDisk else { return }

        var newImages: [(PlatformImage, String)] = []
        var used: Set<ObjectIdentifier> = []
        let pagesOut: [ProjectFile.Page] = pages.map { page in
            let imagesOut: [ProjectFile.Image] = page.images.map { img in
                var file: String? = nil
                if !img.isText && !img.isPlaceholder {
                    let key = ObjectIdentifier(img.image)
                    used.insert(key)
                    if let known = savedImageFiles[key], known.image === img.image {
                        file = known.file
                    } else {
                        let name = UUID().uuidString + "." + ProjectStore.fileExtension(for: img.image)
                        savedImageFiles[key] = (img.image, name)
                        newImages.append((img.image, name))
                        file = name
                    }
                }
                return ProjectFile.Image(
                    id: img.id, file: file, isPlaceholder: img.isPlaceholder, textStyle: img.textStyle,
                    protrusion: img.protrusion?.rawValue, protrusionEffect: img.protrusionEffect.rawValue,
                    protrusionObjects: img.protrusionObjects.map { Array($0).sorted() },
                    pan: [Double(img.panOffset.width), Double(img.panOffset.height)],
                    zoom: Double(img.zoom), rotation: Double(img.rotation),
                    focus: img.focus.map { [Double($0.x), Double($0.y)] },
                    framedByUser: img.framedByUser)
            }
            return ProjectFile.Page(
                images: imagesOut, order: page.order,
                columns: page.layout.columns.map { $0.map(\.imageId) },
                colGrows: page.layout.colGrows.map(Double.init),
                boxGrows: page.layout.boxGrows.map { $0.map(Double.init) },
                style: page.style, look: page.look.file)
        }
        // Forget pictures no longer in the collage (their files go too).
        savedImageFiles = savedImageFiles.filter { used.contains($0.key) }

        let existing = onDisk ? ProjectStore.readFile(currentProjectId) : nil
        let look = currentPage.look.file
        let file = ProjectFile(
            id: currentProjectId, name: existing?.name, created: existing?.created ?? Date(), modified: Date(),
            currentPageIndex: currentPageIndex, pages: pagesOut,
            ratio: ratio.rawValue, canvasWidth: Double(canvasSize.width), canvasHeight: Double(canvasSize.height),
            customWidth: customWidth, customHeight: customHeight, customUnit: customUnit.rawValue,
            canvasMargin: look.canvasMargin, canvasRotation: look.canvasRotation, frame: look.frame,
            overlays: look.overlays, effects: look.effects, hsl: look.hsl, calibration: look.calibration,
            filter: look.filter, filterStrength: look.filterStrength)
        let thumb = hasAnyImages ? renderThumbnail() : nil
        UserDefaults.standard.set(currentProjectId.uuidString, forKey: Self.lastProjectKey)
        projectStore.save(file, newImages: newImages, thumbnail: thumb) { [weak self] in
            self?.projectStore.refresh()
        }
    }

    /// A small picture of the page on screen, for the Collages list.
    private func renderThumbnail(longEdge: CGFloat = 600) -> PlatformImage? {
        isRenderingThumbnail = true
        defer { isRenderingThumbnail = false }
        let view = CollageGridView_Grid(scale: 1.0)
            .frame(width: canvasSize.width, height: canvasSize.height)
            .environmentObject(self)
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(canvasSize)
        renderer.scale = longEdge / max(canvasSize.width, canvasSize.height, 1)
        #if canImport(UIKit)
        return renderer.uiImage
        #else
        return renderer.nsImage
        #endif
    }

    /// Opens a saved collage (the open one is saved first).
    func openProject(_ id: UUID) {
        guard id != currentProjectId || !hasAnyImages else { return }
        saveProjectNow()
        projectStore.flush()
        guard let file = ProjectStore.readFile(id) else { return }
        prepareForOtherCollage()
        currentProjectId = id
        UserDefaults.standard.set(id.uuidString, forKey: Self.lastProjectKey)
        load(file)
    }

    /// Back to the start screen (the Collages list): the open collage is
    /// saved and a blank one takes its place.
    func goToCollages() {
        startNewCollage()
    }

    /// A blank collage (the open one is saved and stays in the list).
    func startNewCollage() {
        saveProjectNow()
        prepareForOtherCollage()
        currentProjectId = UUID()
        clear()
        resetHistory()
    }

    /// Removes a saved collage; removing the open one leaves a blank one.
    func removeProject(_ id: UUID) {
        if id == currentProjectId {
            prepareForOtherCollage()
            currentProjectId = UUID()
            clear()
            resetHistory()
        }
        projectStore.delete(id)
    }

    private func prepareForOtherCollage() {
        autosaveWork?.cancel()
        endTextEditing()
        endProtrusionEditing()
        clearSwapDrag()
        overlayPreview = nil
        savedImageFiles = [:]
    }

    /// Loads the pictures off the main thread, then puts the collage in place.
    private func load(_ file: ProjectFile) {
        isRestoringProject = true
        isLoading = true
        isBusy = true
        let id = file.id
        Task.detached(priority: .userInitiated) {
            var loaded: [UUID: CollageImage] = [:]
            var files: [UUID: String] = [:]
            for page in file.pages {
                for item in page.images {
                    var img: CollageImage
                    if let style = item.textStyle {
                        img = CollageImage.textImage(style: style, id: item.id)
                    } else if item.isPlaceholder {
                        img = CollageImage.emptyPlaceholder(id: item.id)
                    } else if let name = item.file,
                              let picture = PlatformImage(contentsOfFile: ProjectStore.imagesFolder(id).appendingPathComponent(name).path) {
                        img = CollageImage(id: item.id, image: picture)
                        files[item.id] = name
                    } else {
                        continue
                    }
                    img.protrusion = item.protrusion.map(ProtrusionEdges.init(rawValue:))
                    img.protrusionEffect = ProtrusionEffect(rawValue: item.protrusionEffect) ?? .none
                    img.protrusionObjects = item.protrusionObjects.map(Set.init)
                    if item.pan.count == 2 { img.panOffset = CGSize(width: item.pan[0], height: item.pan[1]) }
                    img.zoom = CGFloat(item.zoom)
                    img.rotation = CGFloat(item.rotation)
                    if let f = item.focus, f.count == 2 { img.focus = CGPoint(x: f[0], y: f[1]) }
                    // Older files: a moved photo counts as framed by hand.
                    img.framedByUser = item.framedByUser ?? (img.panOffset != .zero || img.zoom != 1)
                    loaded[item.id] = img
                }
            }
            let images = loaded, imageFiles = files
            await MainActor.run { self.finishLoading(file, images: images, files: imageFiles) }
        }
    }

    private func finishLoading(_ file: ProjectFile, images: [UUID: CollageImage], files: [UUID: String]) {
        var collageLook = PageLook(file: file.collageLook)
        // Files before version 2: Fade on the old ±100 scale.
        func halveFade(_ look: inout PageLook) {
            if file.version < 2, let f = look.effects[.fade] { look.effects[.fade] = (f / 2).rounded() }
        }
        halveFade(&collageLook)
        let restoredPages: [CollagePage] = file.pages.map { p in
            var page = CollagePage(style: p.style, look: p.look.map { PageLook(file: $0) } ?? collageLook)
            if p.look != nil { halveFade(&page.look) }
            page.images = p.images.compactMap { images[$0.id] }
            let present = Set(page.images.map(\.id))
            page.order = p.order.filter { present.contains($0) }
            let columns: [[ColumnItem]] = p.columns.map { col in
                col.compactMap { id in
                    guard let img = images[id], present.contains(id) else { return nil }
                    let s = img.naturalSize
                    return ColumnItem(imageId: id, aspectRatio: s.height / max(s.width, 1))
                }
            }
            // A layout that no longer matches its pictures is re-made.
            let laidOut = Set(columns.flatMap { $0.map(\.imageId) })
            if laidOut == present && columns.count == p.colGrows.count && columns.count == p.boxGrows.count
                && zip(columns, p.boxGrows).allSatisfy({ $0.count == $1.count }) {
                page.layout.columns = columns
                page.layout.colGrows = p.colGrows.map { CGFloat($0) }
                page.layout.boxGrows = p.boxGrows.map { $0.map { CGFloat($0) } }
            } else {
                page.layout.rebuild(images: page.images, order: page.order, numCols: page.style.numCols)
            }
            return page
        }
        let snapshot = CollageSnapshot(
            pages: restoredPages, currentPageIndex: file.currentPageIndex,
            ratio: CanvasRatio(rawValue: file.ratio) ?? .square,
            canvasSize: CGSize(width: file.canvasWidth, height: file.canvasHeight),
            customWidth: file.customWidth, customHeight: file.customHeight,
            customUnit: CustomUnit(rawValue: file.customUnit) ?? .px)
        applyDocument(snapshot)
        Diagnostics.log("opened collage \(diagnosticsSummary)")
        // The pictures already on disk aren't written again.
        savedImageFiles = [:]
        for page in pages {
            for img in page.images {
                if let name = files[img.id] { savedImageFiles[ObjectIdentifier(img.image)] = (img.image, name) }
            }
        }
        imageFrames.removeAll()
        emptySlotFrames.removeAll()
        refreshTrackedGeometry(after: 0.45)
        isRestoringProject = false
        isLoading = false
        isBusy = false
        resetHistory()
        detectFocusPoints()
    }
}

// MARK: - Collages screen

/// The start screen: a "New Collage" tile (straight to the photo picker)
/// and every saved collage, newest first. Shown whenever the open collage
/// has no photos — at launch, and after "Collages" in the editor.
struct CollagesHome: View {
    @EnvironmentObject var state: CollageState
    @ObservedObject var store: ProjectStore
    /// Opens the photo picker for a new collage.
    var onNewCollage: () -> Void
    @State private var renaming: ProjectSummary?
    @State private var newName = ""
    @State private var removing: ProjectSummary?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 18) {
                newTile
                ForEach(store.summaries) { p in
                    tile(p)
                }
            }
            .padding(16)
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Save") {
                if let p = renaming { store.rename(p.id, to: newName) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog("Remove this collage?",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let p = removing { state.removeProject(p.id) }
                removing = nil
            }
            Button("Cancel", role: .cancel) { removing = nil }
        } message: {
            Text("It can't be brought back.")
        }
    }

    private var newTile: some View {
        Button(action: onNewCollage) {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 34, weight: .light))
                            .foregroundColor(.accentColor)
                    }
                Text("New Collage")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.accentColor)
                Text(" ").font(.caption)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New collage")
        .accessibilityHint("Choose photos for a new collage")
    }

    private func tile(_ p: ProjectSummary) -> some View {
        Button {
            state.openProject(p.id)
        } label: {
            VStack(spacing: 8) {
                // A square tile; the thumbnail fills it.
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay { ProjectThumb(url: p.thumbURL, version: p.modified) }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                Text(p.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text("\(p.imageCount) photo\(p.imageCount == 1 ? "" : "s") · \(p.modified.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { newName = p.name; renaming = p } label: { Label("Rename", systemImage: "pencil") }
            Button { store.duplicate(p.id) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            Button(role: .destructive) { removing = p } label: { Label("Remove", systemImage: "trash") }
        }
        .accessibilityLabel("\(p.name), \(p.imageCount) photos")
    }
}

/// A saved collage's thumbnail, read off the main thread.
private struct ProjectThumb: View {
    let url: URL
    let version: Date
    @State private var image: PlatformImage?

    var body: some View {
        ZStack {
            Color.primary.opacity(0.06)
            if let image {
                // The whole collage, fitted (its shape shows on the tile).
                Group {
                    #if canImport(UIKit)
                    Image(uiImage: image).resizable().scaledToFit()
                    #else
                    Image(nsImage: image).resizable().scaledToFit()
                    #endif
                }
                .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                .padding(10)
            }
        }
        .task(id: version) {
            let url = url
            image = await Task.detached(priority: .utility) { PlatformImage(contentsOfFile: url.path) }.value
        }
    }
}

#if DEBUG && canImport(UIKit)
// MARK: - Debug seeding (Simulator checks)

extension CollageState {
    /// `-demoSeed N` on launch, with nothing restored: N generated test
    /// pictures (gradients in mixed shapes), so the app can be exercised in
    /// the Simulator without the photo picker.
    func seedDemoImagesIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        // `-tab N` opens a panel tab; `-showProjects` goes back to the Collages screen.
        if let t = args.firstIndex(of: "-tab"), t + 1 < args.count, let tab = Int(args[t + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.selectedPanelTab = tab
                self.isPanelOpen = true
            }
        }
        if let t = args.firstIndex(of: "-style"), t + 1 < args.count, let n = Int(args[t + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                if StylePreset.builtIns.indices.contains(n) { self.applyStylePreset(StylePreset.builtIns[n]) }
            }
        }
        if let t = args.firstIndex(of: "-fill"), t + 1 < args.count, let kind = BackgroundKind(rawValue: args[t + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.backgroundKind = kind; self.gap = 40 }
        }
                if args.contains("-exportNow") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                Task { await self.exportPages(allPages: true, settings: ExportSettings(size: .instagram, format: .heic)) }
            }
        }
                if args.contains("-export") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.showExportOptions = true }
        }
                if args.contains("-compare") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.compareOriginal = true }
        }
        // `-pageLookDemo`: two pages with different settings, page 1's copied
        // and the paste sheet open (`-pageLookDemo paste` pastes it all onto page 2).
        if let t = args.firstIndex(of: "-pageLookDemo") {
            let pasteNow = t + 1 < args.count && args[t + 1] == "paste"
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                self.colorFilter = .classicNegative
                self.canvasMargin = 60
                self.canvasRotation = 4
                if let last = self.images.last { self.moveImageToNewPage(id: last.id) }
                if self.pages.count > 1 {
                    self.pages[1].look.colorFilter = .amber
                    self.pages[1].look.canvasMargin = 0
                    self.pages[1].look.canvasRotation = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    self.copyPageLook()
                    if pasteNow {
                        self.pastePageLook(Set(PageLookPart.allCases), to: [1])
                        self.goToPage(1)
                    } else {
                        self.pasteToAllOthers = true
                        self.showPastePageLook = true
                    }
                }
            }
        }
        // `-full 1` / `-full 2`: the full-screen preview / only the collage.
        if let t = args.firstIndex(of: "-full"), t + 1 < args.count, let n = Int(args[t + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                self.collapsePanel()
                self.chromeHidden = n >= 1
                self.toolbarHidden = n >= 2
            }
        }
        // `-frame <asset>`: a pack frame on the page.
        if let t = args.firstIndex(of: "-frame"), t + 1 < args.count {
            let name = args[t + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if let f = Self.framePacks.flatMap(\.frames).first(where: { $0.variantAssets.contains(name) }) {
                    self.canvasFrame = f
                }
            }
        }
        // `-onePerPage`: every photo on its own page (lots of rows in Images).
        if args.contains("-onePerPage") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.distributeOneImagePerPage() }
        }
        // `-editsOn`: one edit, so the compare button shows.
        if args.contains("-editsOn") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.effects[.contrast] = 20 }
        }
        // `-newCollage`: the empty start screen (saved collages kept).
        if args.contains("-newCollage") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.startNewCollage() }
        }
        // `-addText` adds a text box (opened in the panel) after the seed;
        // `-textAt N` puts it at position N (and closes the panel).
        if args.contains("-addText") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                self.addTextImage()
                if let t = args.firstIndex(of: "-textAt"), t + 1 < args.count, let n = Int(args[t + 1]),
                   let id = self.images.last(where: \.isText)?.id {
                    self.endTextEditing()
                    self.collapsePanel()
                    var order = self.order.filter { $0 != id }
                    order.insert(id, at: min(n, order.count))
                    self.order = order
                    self.rebuildLayout(resetGrows: true)
                }
            }
        }
        if args.contains("-showProjects") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.goToCollages() }
        }
        guard let i = args.firstIndex(of: "-demoSeed"), !hasAnyImages else { return }
        let count = (i + 1 < args.count ? Int(args[i + 1]) : nil) ?? 4
        let sizes = [CGSize(width: 1200, height: 1600), CGSize(width: 1600, height: 1000),
                     CGSize(width: 1200, height: 1200), CGSize(width: 900, height: 1600)]
        let images: [PlatformImage] = (0..<count).map { n in
            let size = sizes[n % sizes.count]
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
                let hue = CGFloat(n) / CGFloat(max(count, 1))
                let colors = [UIColor(hue: hue, saturation: 0.55, brightness: 0.95, alpha: 1).cgColor,
                              UIColor(hue: hue + 0.12, saturation: 0.7, brightness: 0.55, alpha: 1).cgColor]
                let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil)!
                ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
                UIColor.white.withAlphaComponent(0.85).setFill()
                let r = min(size.width, size.height) * 0.18
                ctx.cgContext.fillEllipse(in: CGRect(x: size.width * 0.7 - r, y: size.height * 0.3 - r, width: r * 2, height: r * 2))
                let label = "\(n + 1)" as NSString
                label.draw(at: CGPoint(x: 40, y: 30), withAttributes: [.font: UIFont.boldSystemFont(ofSize: size.height * 0.12),
                                                                     .foregroundColor: UIColor.white])
            }
        }
        addImages(images)
    }
}
#endif
