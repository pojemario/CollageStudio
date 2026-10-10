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
    var version = 1
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
                style: page.style)
        }
        // Forget pictures no longer in the collage (their files go too).
        savedImageFiles = savedImageFiles.filter { used.contains($0.key) }

        let existing = onDisk ? ProjectStore.readFile(currentProjectId) : nil
        let file = ProjectFile(
            id: currentProjectId, name: existing?.name, created: existing?.created ?? Date(), modified: Date(),
            currentPageIndex: currentPageIndex, pages: pagesOut,
            ratio: ratio.rawValue, canvasWidth: Double(canvasSize.width), canvasHeight: Double(canvasSize.height),
            customWidth: customWidth, customHeight: customHeight, customUnit: customUnit.rawValue,
            canvasMargin: canvasMargin, canvasRotation: canvasRotation, frame: canvasFrame?.baseName,
            overlays: overlayLayers.map {
                ProjectFile.Overlay(asset: $0.asset, kind: $0.kind.rawValue, opacity: $0.opacity, blur: $0.blur,
                                    aboveFrame: $0.aboveFrame, scale: Double($0.scale), rotation: Double($0.rotation),
                                    offset: [Double($0.offset.width), Double($0.offset.height)])
            },
            effects: effects.storage, hsl: hsl.storage, calibration: calibration.storage,
            filter: colorFilter.storageKey, filterStrength: filterStrength)
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

    /// At launch: the collage that was open last time, as it was left.
    func restoreLastProject() {
        guard let raw = UserDefaults.standard.string(forKey: Self.lastProjectKey),
              let id = UUID(uuidString: raw),
              let file = ProjectStore.readFile(id), file.imageCount > 0 else { return }
        currentProjectId = id
        load(file)
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
        let restoredPages: [CollagePage] = file.pages.map { p in
            var page = CollagePage(style: p.style)
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
        let frames = Self.availableFrames + Self.framePacks.flatMap(\.frames)
        let snapshot = CollageSnapshot(
            pages: restoredPages, currentPageIndex: file.currentPageIndex,
            ratio: CanvasRatio(rawValue: file.ratio) ?? .square,
            canvasSize: CGSize(width: file.canvasWidth, height: file.canvasHeight),
            customWidth: file.customWidth, customHeight: file.customHeight,
            customUnit: CustomUnit(rawValue: file.customUnit) ?? .px,
            canvasMargin: file.canvasMargin, canvasRotation: file.canvasRotation,
            canvasFrame: file.frame.flatMap { name in frames.first { $0.baseName == name } },
            overlayLayers: file.overlays.compactMap { o in
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
            effects: effectsFromStorage(file.effects), hsl: HSLAdjustments(storage: file.hsl),
            calibration: CameraCalibration(storage: file.calibration),
            colorFilter: ColorFilter(storageKey: file.filter), filterStrength: file.filterStrength)
        applyDocument(snapshot)
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

/// Every saved collage, newest first, with a big "New Collage" tile.
struct ProjectsView: View {
    @EnvironmentObject var state: CollageState
    @ObservedObject var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    @State private var renaming: ProjectSummary?
    @State private var newName = ""
    @State private var removing: ProjectSummary?

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 18) {
                    newTile
                    ForEach(store.summaries) { p in
                        tile(p)
                    }
                }
                .padding(16)
            }
            .background(ColorManager.canvasAreaBackground.ignoresSafeArea())
            .navigationTitle("Collages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
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
        .onAppear {
            // The open collage shows up to date in the list.
            state.saveProjectNow()
        }
    }

    private var newTile: some View {
        Button {
            state.startNewCollage()
            dismiss()
        } label: {
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
    }

    private func tile(_ p: ProjectSummary) -> some View {
        let isOpen = p.id == state.currentProjectId && state.hasAnyImages
        return Button {
            state.openProject(p.id)
            dismiss()
        } label: {
            VStack(spacing: 8) {
                // A square tile; the thumbnail fills it.
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay { ProjectThumb(url: p.thumbURL, version: p.modified) }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isOpen ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: isOpen ? 2.5 : 1))
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
        .accessibilityLabel("\(p.name), \(p.imageCount) photos\(isOpen ? ", open" : "")")
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

/// On the empty start screen: the way back to saved collages.
struct RecentCollagesButton: View {
    @EnvironmentObject var state: CollageState
    @ObservedObject var store: ProjectStore

    var body: some View {
        if !store.summaries.isEmpty {
            Button { state.showProjects = true } label: {
                Label("Your collages (\(store.summaries.count))", systemImage: "square.stack")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(.ultraThinMaterial))
                    .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
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
        // `-tab N` opens a panel tab; `-showProjects` the Collages screen.
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
                if args.contains("-export") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.showExportOptions = true }
        }
                if args.contains("-compare") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self.compareOriginal = true }
        }
                if args.contains("-showProjects") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.showProjects = true }
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
