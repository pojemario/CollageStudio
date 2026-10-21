import SwiftUI
import Combine

// MARK: - Stored forms

extension PageStyle: Codable {
    private enum CodingKeys: String, CodingKey {
        case numCols, isRows, isStrip, slides, gap, cornerRadius, backgroundColor, borderColor, borderThickness
        case borderStyle, borderPlacement, linkBorderToBackground, backgroundKind, backgroundColor2
    }

    /// Missing or unknown entries keep their defaults, so older files load.
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        numCols = max(1, try c.decodeIfPresent(Int.self, forKey: .numCols) ?? numCols)
        isRows = try c.decodeIfPresent(Bool.self, forKey: .isRows) ?? isRows
        isStrip = try c.decodeIfPresent(Bool.self, forKey: .isStrip) ?? isStrip
        slides = min(max(try c.decodeIfPresent(Int.self, forKey: .slides) ?? slides, 1), CollageState.maxSlides)
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
        if isStrip { try c.encode(isStrip, forKey: .isStrip) }
        if slides > 1 { try c.encode(slides, forKey: .slides) }
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
        case .amber2: return "amber2"
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
        case "amber2": self = .amber2
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
    // Never below a slider's range (an old negative Fade becomes none).
    for (k, v) in d { if let e = CollageEffect(rawValue: k) { out[e] = max(v, e.range.lowerBound) } }
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
    /// Build 89 only: every page this many pictures wide, with the canvas
    /// size above that wide. (Pages now keep their own width.)
    var slides: Int? = nil

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
        /// The photo's own edits (missing: none, and in older files).
        var edit: Edit?
    }

    /// A photo's own Edit settings.
    struct Edit: Codable {
        var effects: [String: Double]
        var hsl: [String: [Double]]
        var calibration: [Double]
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
        /// The slide of a carousel strip it fills (missing: the whole canvas).
        var slide: Int? = nil
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
                                    offset: [Double($0.offset.width), Double($0.offset.height)], slide: $0.slide)
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
                layer.slide = o.slide.map { max($0, 0) }
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
        do {
            return try JSONDecoder().decode(ProjectFile.self, from: data)
        } catch {
            Diagnostics.log("unreadable collage \(id.uuidString.prefix(8)): \(error)")
            return nil
        }
    }

    /// Writes a collage: new photo files first, then the thumbnail and the
    /// JSON (atomically), then drops photo files it no longer uses (never
    /// one in `protected`). If a photo or the JSON can't be written, the
    /// files on disk are left as they were and `completion` gets the photo
    /// files that didn't make it (or false), so the next save tries again.
    /// Runs to the end even if the app leaves the screen meanwhile.
    func save(_ file: ProjectFile, newImages: [(PlatformImage, String)], thumbnail: PlatformImage?,
              protected: Set<String> = [], completion: @escaping (_ saved: Bool, _ unwritten: Set<String>) -> Void) {
        let id = file.id
        let keep = Set(file.pages.flatMap { $0.images.compactMap(\.file) }).union(protected)
        #if canImport(UIKit)
        let task = UIApplication.shared.beginBackgroundTask(withName: "Save collage")
        #endif
        io.async {
            let fm = FileManager.default
            var unwritten: Set<String> = []
            do {
                try fm.createDirectory(at: Self.imagesFolder(id), withIntermediateDirectories: true)
                for (image, name) in newImages {
                    let url = Self.imagesFolder(id).appendingPathComponent(name)
                    guard !fm.fileExists(atPath: url.path) else { continue }
                    guard let data = Self.encode(image, name: name) else { unwritten.insert(name); continue }
                    do { try data.write(to: url, options: .atomic) } catch { unwritten.insert(name) }
                }
            } catch {
                unwritten = Set(newImages.map(\.1))
            }
            var saved = false
            // A photo missing on disk: keep the last good JSON (and every
            // file it names) rather than write one that points at nothing.
            if unwritten.isEmpty, let data = try? JSONEncoder().encode(file) {
                do {
                    try data.write(to: Self.jsonURL(id), options: .atomic)
                    saved = true
                } catch {}
            }
            if saved {
                if let thumbnail, let data = Self.jpeg(thumbnail, quality: 0.8) {
                    try? data.write(to: Self.thumbURL(id), options: .atomic)
                }
                let present = (try? fm.contentsOfDirectory(atPath: Self.imagesFolder(id).path)) ?? []
                for name in present where !keep.contains(name) {
                    try? fm.removeItem(at: Self.imagesFolder(id).appendingPathComponent(name))
                }
            } else {
                Diagnostics.log("save failed for collage \(id.uuidString.prefix(8)) (\(unwritten.count) photo files)")
            }
            DispatchQueue.main.async {
                completion(saved, unwritten)
                #if canImport(UIKit)
                UIApplication.shared.endBackgroundTask(task)
                #endif
            }
        }
    }

    /// Waits for pending writes (e.g. before opening another collage).
    func flush() { io.sync {} }

    func delete(_ id: UUID) {
        io.sync { try? FileManager.default.removeItem(at: Self.folder(id)) }
        refresh()
    }

    func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Read in the queue, after any save still pending for this collage,
        // so the rename never writes back an older version.
        io.sync {
            guard var file = Self.readFile(id) else { return }
            file.name = trimmed.isEmpty ? nil : String(trimmed.prefix(80))
            if let data = try? JSONEncoder().encode(file) {
                try? data.write(to: Self.jsonURL(id), options: .atomic)
            }
        }
        refresh()
    }

    /// A copy under a new id, named "… copy".
    func duplicate(_ id: UUID) {
        let newId = UUID()
        io.sync {
            // (In the queue: after a pending save of the original.)
            guard var file = Self.readFile(id) else { return }
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
        hasUnsavedChanges = true
        autosaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveProjectNow() }
        autosaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    /// Writes the open collage now (if there's anything to keep).
    func saveProjectNow() {
        guard !isRestoringProject else { return }
        // Edits from the last moment (history waits for them to settle, or
        // for a finger to lift) still count.
        commitHistoryIfChanged()
        if let committed = historyCommitted, !documentSnapshot.sameDocument(as: committed) {
            hasUnsavedChanges = true
        }
        autosaveWork?.cancel()
        autosaveWork = nil
        let onDisk = FileManager.default.fileExists(atPath: ProjectStore.jsonURL(currentProjectId).path)
        // An empty collage isn't written: a new one isn't worth a file, and
        // one emptied photo by photo keeps its last version in the list
        // (so removing the last photo can't lose the whole collage; it's
        // deleted from the Collages list on purpose).
        guard hasAnyImages else { return }
        // Nothing changed since it was opened or saved: the file (and its
        // thumbnail) are already right.
        guard hasUnsavedChanges || !onDisk else { return }
        hasUnsavedChanges = false

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
                    framedByUser: img.framedByUser,
                    edit: img.edit.isIdentity ? nil
                        : ProjectFile.Edit(effects: img.edit.effects.storage, hsl: img.edit.hsl.storage,
                                           calibration: img.edit.calibration.storage))
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
            ratio: ratio.rawValue, canvasWidth: Double(pictureSize.width), canvasHeight: Double(pictureSize.height),
            customWidth: customWidth, customHeight: customHeight, customUnit: customUnit.rawValue,
            canvasMargin: look.canvasMargin, canvasRotation: look.canvasRotation, frame: look.frame,
            overlays: look.overlays, effects: look.effects, hsl: look.hsl, calibration: look.calibration,
            filter: look.filter, filterStrength: look.filterStrength)
        let thumb = hasAnyImages ? renderThumbnail() : nil
        Diagnostics.log("saved collage \(currentProjectId.uuidString.prefix(8)) thumb \(thumb.map { "\(Int($0.size.width))x\(Int($0.size.height))" } ?? "none")")
        UserDefaults.standard.set(currentProjectId.uuidString, forKey: Self.lastProjectKey)
        let savingId = currentProjectId
        projectStore.save(file, newImages: newImages, thumbnail: thumb, protected: unloadedImageFiles) { [weak self] saved, unwritten in
            guard let self else { return }
            if !saved {
                // Try again with the next save: forget the photo files that
                // weren't written, and keep the collage marked as changed.
                savedImageFiles = savedImageFiles.filter { !unwritten.contains($0.value.file) }
                if currentProjectId == savingId { hasUnsavedChanges = true }
            }
            projectStore.refresh()
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
        // One at a time: two loads finishing out of order could put one
        // collage under the other's id.
        guard !isRestoringProject else { return }
        saveProjectNow()
        projectStore.flush()
        guard let file = ProjectStore.readFile(id) else { return }
        prepareForOtherCollage()
        currentProjectId = id
        UserDefaults.standard.set(id.uuidString, forKey: Self.lastProjectKey)
        // A saved collage opens with no tab chosen and the panel down.
        panelTabShown = false
        isPanelOpen = false
        load(file)
    }

    /// Back to the start screen (the Collages list): the open collage is
    /// saved and a blank one takes its place.
    func goToCollages() {
        Diagnostics.log("to Collages · changed \(hasUnsavedChanges) · \(diagnosticsSummary)")
        startNewCollage()
    }

    /// A blank collage (the open one is saved and stays in the list).
    func startNewCollage() {
        saveProjectNow()
        prepareForOtherCollage()
        currentProjectId = UUID()
        clear()
        resetHistory()
        hasUnsavedChanges = false
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
        selectedImageId = nil
        photoEditTargetId = nil
        unloadedImageFiles = []
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
            var unloaded: Set<String> = []
            for page in file.pages {
                for item in page.images {
                    var img: CollageImage
                    if let style = item.textStyle {
                        img = CollageImage.textImage(style: style, id: item.id)
                    } else if item.isPlaceholder {
                        img = CollageImage.emptyPlaceholder(id: item.id)
                    } else if let name = item.file,
                              let data = try? Data(contentsOf: ProjectStore.imagesFolder(id).appendingPathComponent(name)),
                              let picture = PlatformImage.decoded(from: data) {
                        img = CollageImage(id: item.id, image: picture)
                        files[item.id] = name
                    } else {
                        // Missing or unreadable now (low memory?): its file
                        // is kept on disk, never cleaned up as unused.
                        if let name = item.file { unloaded.insert(name) }
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
                    if let e = item.edit {
                        img.edit = PhotoEdit(effects: effectsFromStorage(e.effects), hsl: HSLAdjustments(storage: e.hsl),
                                             calibration: CameraCalibration(storage: e.calibration))
                    }
                    loaded[item.id] = img
                }
            }
            let images = loaded, imageFiles = files, unloadedFiles = unloaded
            if !unloadedFiles.isEmpty { Diagnostics.log("collage opened without \(unloadedFiles.count) photos") }
            await MainActor.run {
                self.unloadedImageFiles = unloadedFiles
                self.finishLoading(file, images: images, files: imageFiles)
            }
        }
    }

    private func finishLoading(_ file: ProjectFile, images: [UUID: CollageImage], files: [UUID: String]) {
        var collageLook = PageLook(file: file.collageLook)
        // Files before version 2: Fade on the old ±100 scale.
        func halveFade(_ look: inout PageLook) {
            if file.version < 2, let f = look.effects[.fade] { look.effects[.fade] = (f / 2).rounded() }
        }
        halveFade(&collageLook)
        // Build 89 made every page equally wide, kept at the top level.
        let legacySlides = min(max(file.slides ?? 1, 1), Self.maxSlides)
        let restoredPages: [CollagePage] = file.pages.map { p in
            var page = CollagePage(style: p.style, look: p.look.map { PageLook(file: $0) } ?? collageLook)
            if legacySlides > 1 && page.style.slides == 1 { page.style.slides = legacySlides }
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
                page.layout.rebuild(images: page.images, order: page.order, numCols: page.style.numCols, strip: page.style.isStrip)
            }
            return page
        }
        let snapshot = CollageSnapshot(
            pages: restoredPages, currentPageIndex: file.currentPageIndex,
            ratio: CanvasRatio(rawValue: file.ratio) ?? .square,
            pictureSize: CGSize(width: file.canvasWidth / Double(legacySlides), height: file.canvasHeight),
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
        hasUnsavedChanges = false
        detectFocusPoints()
        // Protruding photos need their subject found again (masks aren't
        // saved) before the protrusion can be drawn.
        for page in pages {
            for img in page.images where img.protrusion != nil { requestSubjectMask(for: img) }
        }
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
    /// Select mode: tiles toggle a check instead of opening, for removing
    /// several collages at once.
    @State private var selecting = false
    @State private var selected: Set<UUID> = []
    @State private var confirmingBatch = false

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if !store.summaries.isEmpty { header }
                LazyVGrid(columns: columns, spacing: 18) {
                    newTile
                        .disabled(selecting)
                        .opacity(selecting ? 0.35 : 1)
                    ForEach(store.summaries) { p in
                        tile(p)
                    }
                }
            }
            .padding(16)
        }
        .safeAreaInset(edge: .bottom) {
            if selecting { deleteBar }
        }
        .animation(.easeInOut(duration: 0.2), value: selecting)
        .onChange(of: store.summaries) { _, list in
            selected.formIntersection(list.map(\.id))
            if list.isEmpty { selecting = false }
        }
        .confirmationDialog(selected.count == 1 ? "Remove this collage?" : "Remove \(selected.count) collages?",
                            isPresented: $confirmingBatch, titleVisibility: .visible) {
            Button(selected.count == 1 ? "Remove" : "Remove \(selected.count)", role: .destructive) {
                for id in selected { state.removeProject(id) }
                selected = []
                selecting = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They can't be brought back.")
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

    /// "Saved Collages" with Select / Done (and Select All while selecting).
    private var header: some View {
        HStack {
            Text(selecting ? (selected.isEmpty ? "Select Collages" : "\(selected.count) Selected") : "Saved Collages")
                .font(.headline)
                .monospacedDigit()
            Spacer()
            if selecting {
                let all = selected.count == store.summaries.count
                Button(all ? "Deselect All" : "Select All") {
                    selected = all ? [] : Set(store.summaries.map(\.id))
                }
                .padding(.trailing, 12)
            }
            Button(selecting ? "Done" : "Select") {
                selecting.toggle()
                selected = []
            }
            .fontWeight(.semibold)
        }
        .font(.subheadline)
    }

    /// While selecting: removes the checked collages (after a confirmation).
    private var deleteBar: some View {
        Button(role: .destructive) {
            confirmingBatch = true
        } label: {
            Label(selected.isEmpty ? "Remove" : "Remove \(selected.count)", systemImage: "trash")
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Capsule().fill(Color.red.opacity(selected.isEmpty ? 0.35 : 0.9)))
        }
        .buttonStyle(.plain)
        .disabled(selected.isEmpty)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
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
            // The whole tile takes the tap, not just the + and the dashed
            // line (the box's inside is empty, so it wouldn't otherwise).
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("New collage")
        .accessibilityHint("Choose photos for a new collage")
    }

    private func tile(_ p: ProjectSummary) -> some View {
        let isSelected = selected.contains(p.id)
        return Button {
            if selecting {
                if isSelected { selected.remove(p.id) } else { selected.insert(p.id) }
            } else {
                state.openProject(p.id)
            }
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
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Color.accentColor, lineWidth: 3)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if selecting {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 24, weight: .medium))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(Color.white,
                                                 isSelected ? Color.accentColor : Color.black.opacity(0.25))
                                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                                .padding(8)
                        }
                    }
                // Toned down, so the thumbnails lead.
                Text(p.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.primary.opacity(0.6))
                    .lineLimit(1)
                Text("\(p.imageCount) photo\(p.imageCount == 1 ? "" : "s") · \(p.modified.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))
                    .lineLimit(1)
            }
            // Whole tile, even before (or without) its thumbnail.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { selecting = true; selected.insert(p.id) } label: { Label("Select", systemImage: "checkmark.circle") }
            Button { newName = p.name; renaming = p } label: { Label("Rename", systemImage: "pencil") }
            Button { store.duplicate(p.id) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            Button(role: .destructive) { removing = p } label: { Label("Remove", systemImage: "trash") }
        }
        .accessibilityLabel("\(p.name), \(p.imageCount) photos")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A saved collage's thumbnail. Read from disk as its tile appears (a
/// small JPEG, a few milliseconds) and kept in memory for the session, so
/// coming back to the Collages screen shows every thumbnail at once.
/// (Loading it in the background lost out to the photo analysis a just
/// opened collage starts, and an evictable cache could come back empty.)
private struct ProjectThumb: View {
    let url: URL
    let version: Date
    @State private var image: PlatformImage?

    /// Thumbnails by file and save time (a re-saved collage gets a new one).
    @MainActor private static var cache: [String: PlatformImage] = [:]
    private var key: String { "\(url.path)#\(version.timeIntervalSinceReferenceDate)" }

    var body: some View {
        ZStack {
            Color.primary.opacity(0.06)
            if let image = image ?? Self.cache[key] {
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
        .onAppear(perform: load)
        .onChange(of: key) { load() }
    }

    private func load() {
        if let hit = Self.cache[key] {
            image = hit
            return
        }
        guard let img = PlatformImage(contentsOfFile: url.path) else {
            let exists = FileManager.default.fileExists(atPath: url.path)
            Diagnostics.log("thumb load failed \(url.deletingLastPathComponent().lastPathComponent.prefix(8)) file \(exists ? "there" : "missing")")
            return
        }
        // Drop the collage's older thumbnails (other save times).
        let prefix = url.path + "#"
        for k in Self.cache.keys where k.hasPrefix(prefix) { Self.cache[k] = nil }
        Self.cache[key] = img
        image = img
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
            // After -openNewest has opened its collage (which lowers the panel).
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                self.panelTabShown = true
                if let p = args.firstIndex(of: "-looksPage"), p + 1 < args.count,
                   let page = LooksPanel.Page(rawValue: args[p + 1]) { self.looksPage = page }
                if let p = args.firstIndex(of: "-layoutPage"), p + 1 < args.count,
                   let page = LayoutPanel.Page(rawValue: args[p + 1]) { self.layoutPage = page }
                self.selectedPanelTab = tab
                self.isPanelOpen = true
            }
        }
        // `-slides N` cuts the opened collage into N slides; `-exportTest`
        // then exports it (files logged, left in tmp/CollageExport).
        if let t = args.firstIndex(of: "-slides"), t + 1 < args.count, let n = Int(args[t + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                self.setSlides(n)
                if args.contains("-strip") { self.setLanes(.strip) }
                if args.contains("-allSlides") { self.slideFocus = nil }
                // `-overlayPack Name` picks the pack (else the first).
                let packName = args.firstIndex(of: "-overlayPack").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
                if args.contains("-addOverlay"),
                   let pack = CollageState.overlayPacks.first(where: { $0.name == packName }) ?? CollageState.overlayPacks.first,
                   let asset = pack.assets.first {
                    self.slideFocus = 1
                    self.addOverlayLayer(asset: asset, kind: pack.kind)
                }
                if args.contains("-openRatio") { self.openRatio() }
            }
        }
        if let t = args.firstIndex(of: "-picture"), t + 1 < args.count, let k = Int(args[t + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { self.goToPicture(k) }
        }
        // `-sharpTest` puts a big, finely detailed test pattern in the biggest
        // box, to see the sharp copy replace the proxy.
        if args.contains("-sharpTest") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                let size = CGSize(width: 3000, height: 4000)
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                let pattern = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
                    UIColor.white.setFill()
                    ctx.fill(CGRect(origin: .zero, size: size))
                    UIColor.black.setFill()
                    for x in stride(from: 0, to: size.width, by: 12) {
                        ctx.fill(CGRect(x: x, y: 0, width: 3, height: size.height))
                    }
                    let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 60),
                                                                .foregroundColor: UIColor.systemRed,
                                                                .backgroundColor: UIColor.white]
                    for y in stride(from: 100, to: size.height, by: 300) {
                        ("Sharp copy test 0123456789" as NSString).draw(at: CGPoint(x: 80, y: y), withAttributes: attrs)
                    }
                }
                let pi = self.currentPageIndex
                let boxes = self.pages[pi].images
                if let k = boxes.indices.max(by: { boxes[$0].lastBoxSize.width * boxes[$0].lastBoxSize.height
                                                   < boxes[$1].lastBoxSize.width * boxes[$1].lastBoxSize.height }) {
                    self.pages[pi].images[k].setImage(pattern)
                }
            }
        }
        // `-selectPhoto [N]` selects the current page's first (or Nth) photo.
        if let t = args.firstIndex(of: "-selectPhoto") {
            let n = t + 1 < args.count ? Int(args[t + 1]) ?? 0 : 0
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                let photos = self.currentPage.images.filter { !$0.isPlaceholder }
                if !photos.isEmpty { self.selectImage(photos[min(n, photos.count - 1)].id) }
            }
        }
        // `-pagerTour` steps through every picture and back, like the arrows.
        if args.contains("-pagerTour") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                let n = self.pictureCount
                let path = Array(0..<n) + Array((0..<max(n - 1, 0)).reversed())
                for (i, k) in path.enumerated() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 1.5) { self.goToPicture(k) }
                }
            }
        }
        if args.contains("-exportTest") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                Task {
                    await self.exportPages(allPages: true, settings: ExportSettings(size: .instagram, format: .jpeg))
                    for url in self.exportedFiles {
                        let img = UIImage(contentsOfFile: url.path)
                        Diagnostics.log("exported \(url.lastPathComponent) \(Int(img?.size.width ?? 0))x\(Int(img?.size.height ?? 0))")
                    }
                    self.showExportSheet = false
                }
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
        // `-historyTest`: two edits, two undos, one redo — logs canRedo after.
        if args.contains("-historyTest") {
            let steps: [(Double, () -> Void)] = [
                (3.0, { self.effects[.contrast] = 20 }), (4.0, { self.effects[.contrast] = 40 }),
                (5.0, { self.undo() }), (6.0, { self.undo() }), (7.0, { self.redo() }),
                (9.0, { Diagnostics.log("historyTest canRedo \(self.canRedo) canUndo \(self.canUndo)") }),
            ]
            for (t, step) in steps { DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: step) }
        }
        // `-undoOnce`: undoes the first edit (with -editsOn), so Redo shows.
        if args.contains("-undoOnce") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { self.undo() }
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
        // `-openNewest`: opens the most recent saved collage.
        if args.contains("-openNewest") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if let p = self.projectStore.summaries.first { self.openProject(p.id) }
            }
        }
        // `-photoEditTest`: Edit Photo on the first photo, warmer and brighter.
        if args.contains("-photoEditTest") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                guard let id = self.images.first?.id else { return }
                self.selectImage(id)
                self.beginPhotoEdit(id: id)
                self.editEffects = [.exposure: 40, .temperature: 70, .contrast: 30]
            }
        }
                // `-selectPhoto`: selects the first photo (its tools in the tab bar).
        if args.contains("-selectPhoto") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.selectImage(self.images.first?.id) }
        }
                if args.contains("-showProjects") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { self.goToCollages() }
        }
        // `-autoTest`: presses Edit → Auto once the photos are in.
        if args.contains("-autoTest") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                Diagnostics.log("autoTest press")
                self.toggleAuto()
            }
        }
        // `-demoPhotos <folder>`: real pictures from a Mac folder (the
        // Simulator sees the Mac's disk), instead of generated ones.
        if let d = args.firstIndex(of: "-demoPhotos"), d + 1 < args.count, !hasAnyImages {
            let dir = URL(fileURLWithPath: args[d + 1])
            let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            let pictures = files.prefix(12).compactMap { (try? Data(contentsOf: $0)).flatMap { PlatformImage.decoded(from: $0) } }
            if !pictures.isEmpty { addImages(pictures); return }
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
