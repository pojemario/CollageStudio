import SwiftUI

#if DEBUG && canImport(UIKit)
// MARK: - UI tests (CollageStudioUITests)

/// `-uiTesting` on launch (only Debug builds, as the UI tests run them):
/// collages are kept in their own folder, emptied at launch (unless
/// `-uiTestKeepData`), so tests never see or touch the real ones; the
/// "New Collage" tile adds generated photos instead of opening the photo
/// picker (`-uiTestPhotos N`, 6 by default); and a hidden element
/// (`uitest.probe`) reports the app's state for the tests to check.
enum UITest {
    static let isOn = ProcessInfo.processInfo.arguments.contains("-uiTesting")

    static var projectsFolderName: String { isOn ? "UITestProjects" : "Projects" }
    static let failSaves = isOn && ProcessInfo.processInfo.arguments.contains("-uiTestFailSaves")
    static let slowExport = isOn && ProcessInfo.processInfo.arguments.contains("-uiTestSlowExport")
    /// Pictures put into Photos since launch.
    @MainActor static var savedToPhotos = 0

    /// Before anything reads the collages.
    static func prepare() {
        guard isOn else { return }
        let args = ProcessInfo.processInfo.arguments
        if !args.contains("-uiTestKeepData") {
            try? FileManager.default.removeItem(at: ProjectStore.root)
        }
        // `-uiTestFixtures`: collages saved by earlier builds (the Debug
        // build carries them; see CollageStudioUITests/Fixtures).
        if args.contains("-uiTestFixtures"),
           let fixtures = Bundle.main.url(forResource: "UITestFixtures", withExtension: nil) {
            let fm = FileManager.default
            try? fm.createDirectory(at: ProjectStore.root, withIntermediateDirectories: true)
            for build in (try? fm.contentsOfDirectory(at: fixtures, includingPropertiesForKeys: nil)) ?? [] {
                for project in (try? fm.contentsOfDirectory(at: build, includingPropertiesForKeys: nil)) ?? []
                where UUID(uuidString: project.lastPathComponent) != nil {
                    try? fm.copyItem(at: project, to: ProjectStore.root.appendingPathComponent(project.lastPathComponent))
                }
            }
        }
        // Instant transitions: taps don't wait on (or land mid-) animation.
        if args.contains("-uiTestNoAnimations") { UIView.setAnimationsEnabled(false) }
    }

    private static var photoCount: Int {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-uiTestPhotos"), i + 1 < args.count, let n = Int(args[i + 1]) else { return 6 }
        return max(1, min(n, 30))
    }

    /// Photo-sized JPEGs (as from a phone camera, mixed orientations),
    /// read in through the same path as picked photos.
    static func makePhotos() async -> [CollageImage] {
        let n = photoCount
        var out: [CollageImage] = []
        for k in 0..<n {
            let img = await Task.detached(priority: .userInitiated) {
                autoreleasepool { () -> CollageImage? in
                    guard let data = jpeg(k, of: n) else { return nil }
                    return CollageImage(data: data)
                }
            }.value
            if let img { out.append(img) }
        }
        return out
    }

    private static func jpeg(_ k: Int, of n: Int) -> Data? {
        // `-uiTestSubject`: photos with a clear subject, for Cutout.
        if ProcessInfo.processInfo.arguments.contains("-uiTestSubject") { return subjectJPEG() }
        let sizes = [CGSize(width: 3024, height: 4032), CGSize(width: 4032, height: 3024),
                     CGSize(width: 3024, height: 3024), CGSize(width: 2268, height: 4032)]
        let size = sizes[k % sizes.count]
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let hue = CGFloat(k) / CGFloat(max(n, 1))
            let colors = [UIColor(hue: hue, saturation: 0.5, brightness: 0.95, alpha: 1).cgColor,
                          UIColor(hue: hue + 0.15, saturation: 0.75, brightness: 0.45, alpha: 1).cgColor]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil)!
            ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            // Some detail, so sharpening and clarity have work to do.
            UIColor.white.withAlphaComponent(0.25).setFill()
            for x in stride(from: 0, to: size.width, by: 48) {
                ctx.fill(CGRect(x: x, y: 0, width: 6, height: size.height))
            }
            UIColor.white.withAlphaComponent(0.85).setFill()
            let r = min(size.width, size.height) * 0.18
            ctx.cgContext.fillEllipse(in: CGRect(x: size.width * 0.65 - r, y: size.height * 0.35 - r, width: r * 2, height: r * 2))
            ("\(k + 1)" as NSString).draw(at: CGPoint(x: 80, y: 60),
                                          withAttributes: [.font: UIFont.boldSystemFont(ofSize: size.height * 0.12),
                                                           .foregroundColor: UIColor.white])
        }
        return image.jpegData(compressionQuality: 0.85)
    }

    /// A dark figure (head and shoulders) on a plain light wall, the kind
    /// of picture subject lifting finds a subject in.
    private static func subjectJPEG() -> Data? {
        let size = CGSize(width: 3024, height: 4032)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let c = ctx.cgContext
            UIColor(white: 0.92, alpha: 1).setFill()
            c.fill(CGRect(origin: .zero, size: size))
            c.setShadow(offset: CGSize(width: 30, height: 40), blur: 80, color: UIColor(white: 0, alpha: 0.35).cgColor)
            UIColor(red: 0.2, green: 0.25, blue: 0.4, alpha: 1).setFill()
            c.addPath(UIBezierPath(roundedRect: CGRect(x: 612, y: 2200, width: 1800, height: 2100), cornerRadius: 700).cgPath)
            c.fillPath()
            UIColor(red: 0.85, green: 0.62, blue: 0.5, alpha: 1).setFill()
            c.fillEllipse(in: CGRect(x: 1062, y: 950, width: 900, height: 1150))
            UIColor(red: 0.25, green: 0.15, blue: 0.1, alpha: 1).setFill()
            c.fillEllipse(in: CGRect(x: 1022, y: 850, width: 980, height: 600))
        }
        return image.jpegData(compressionQuality: 0.9)
    }

    /// The app's memory in MB, as the system counts it against its limit.
    static func footprintMB() -> Int { Int(Diagnostics.memoryFootprint() / 1_048_576) }
}

/// Hidden: the app's state as `key=value` pairs, for the UI tests.
/// Refreshed with every state change, and every half second for memory.
struct UITestProbe: View {
    @EnvironmentObject var state: CollageState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier("uitest.probe")
                .accessibilityLabel(summary)
        }
        .allowsHitTesting(false)
    }

    private var summary: String {
        let s = state
        let fields: [(String, Any)] = [
            // Every page's.
            ("photos", s.pages.reduce(0) { $0 + $1.images.filter { !$0.isPlaceholder && !$0.isText }.count }),
            ("pages", s.pages.count),
            ("page", s.currentPageIndex),
            ("post", s.currentPicture),
            ("posts", s.pictureCount),
            ("filter", s.colorFilter.storageKey),
            ("strength", Int(s.filterStrength.rounded())),
            ("fullscreen", s.toolbarHidden ? 1 : 0),
            ("panel", s.isPanelOpen ? 1 : 0),
            ("tab", s.selectedPanelTab),
            ("tabshown", s.panelTabShown ? 1 : 0),
            ("selected", s.selectedImageId == nil ? 0 : 1),
            ("photoedit", s.photoEditTargetId == nil ? 0 : 1),
            ("undo", s.canUndo ? 1 : 0),
            ("redo", s.canRedo ? 1 : 0),
            ("exporting", s.isExporting ? 1 : 0),
            ("exported", s.exportedFiles.count),
            ("busy", s.isBusy || s.isLoading || s.isRestoringProject ? 1 : 0),
            ("collages", s.projectStore.summaries.count),
            // Photos of the open collage whose files didn't load.
            ("unloaded", s.unloadedImageFiles.count),
            ("cutouts", s.pages.reduce(0) { $0 + $1.images.filter { $0.protrusion != nil }.count }),
            ("cutoutedit", s.protrusionTargetId == nil ? 0 : 1),
            // The photo in Cutout: subject found 1, none 0, still looking -1.
            ("subject", subjectState),
            ("ratio", s.ratio.rawValue),
            // Looks sliders off zero on the page.
            ("edits", s.effects.values.filter { $0 != 0 }.count),
            ("savefailed", s.saveFailed ? 1 : 0),
            ("savedtophotos", UITest.savedToPhotos),
            // The toast showing, spaces as underscores.
            ("toast", (s.historyToast ?? "").replacingOccurrences(of: " ", with: "_")),
            ("mem", UITest.footprintMB()),
        ]
        return fields.map { "\($0.0)=\($0.1)" }.joined(separator: " ")
    }

    private var subjectState: Int {
        guard let id = state.protrusionTargetId, let img = state.images.first(where: { $0.id == id }),
              let mask = state.subjectMask(for: img) else { return -1 }
        return mask.mask == nil ? 0 : 1
    }
}
#endif
