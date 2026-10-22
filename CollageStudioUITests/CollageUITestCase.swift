import XCTest

/// Launches the app in its UI-test mode (see UITestSupport.swift in the
/// app): its own empty collage storage, generated photos for "New
/// Collage", and the `uitest.probe` element reporting the app's state as
/// `key=value` pairs (photos, pages, filter, fullscreen, exported, mem, …).
class CollageUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        // A picture of the screen when a test fails, and the state then.
        if let run = testRun, run.failureCount > 0, app.state == .runningForeground {
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "failure"
            shot.lifetime = .keepAlways
            add(shot)
            let probe = XCTAttachment(string: probeText)
            probe.name = "probe"
            probe.lifetime = .keepAlways
            add(probe)
        }
    }

    // MARK: - Launching

    func launch(photos: Int = 6, keepData: Bool = false, extra: [String] = []) {
        app.launchArguments = ["-uiTesting", "-noTips", "-uiTestPhotos", "\(photos)"]
            + (keepData ? ["-uiTestKeepData"] : []) + extra
        app.launch()
        XCTAssertTrue(probe.waitForExistence(timeout: 15), "the app didn't start in UI-test mode")
    }

    // MARK: - The app's state

    var probe: XCUIElement { app.descendants(matching: .any)["uitest.probe"] }

    var probeText: String { probe.exists ? probe.label : "" }

    var state: [String: String] {
        Dictionary(probeText.split(separator: " ").compactMap { pair -> (String, String)? in
            let kv = pair.split(separator: "=", maxSplits: 1)
            return kv.count == 2 ? (String(kv[0]), String(kv[1])) : nil
        }, uniquingKeysWith: { $1 })
    }

    func int(_ key: String) -> Int { Int(state[key] ?? "") ?? -1 }

    /// Waits until the probe shows `key` matching; fails the test otherwise.
    @discardableResult
    func wait(_ key: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line,
              _ check: (String) -> Bool) -> String {
        let end = Date().addingTimeInterval(timeout)
        var last = ""
        while Date() < end {
            last = state[key] ?? ""
            if check(last) { return last }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTFail("\(key) was \"\(last)\" after \(Int(timeout)) s · \(probeText)", file: file, line: line)
        return last
    }

    func wait(_ key: String, is value: String, timeout: TimeInterval = 10,
              file: StaticString = #filePath, line: UInt = #line) {
        wait(key, timeout: timeout, file: file, line: line) { $0 == value }
    }

    func wait(_ key: String, is value: Int, timeout: TimeInterval = 10,
              file: StaticString = #filePath, line: UInt = #line) {
        wait(key, timeout: timeout, file: file, line: line) { $0 == "\(value)" }
    }

    /// Nothing loading, opening or exporting.
    func waitIdle(timeout: TimeInterval = 20, file: StaticString = #filePath, line: UInt = #line) {
        wait("busy", is: 0, timeout: timeout, file: file, line: line)
        wait("exporting", is: 0, timeout: timeout, file: file, line: line)
    }

    // MARK: - Elements

    func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    func button(_ label: String) -> XCUIElement { app.buttons[label].firstMatch }

    func tap(_ e: XCUIElement, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(e.waitForExistence(timeout: timeout), "\(e) isn't there · \(probeText)", file: file, line: line)
        e.tap()
    }

    var collageTiles: XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'collage.'"))
    }

    /// The collage's boxes ("Photo 2 of 6").
    func photo(_ n: Int) -> XCUIElement {
        app.images.matching(NSPredicate(format: "label BEGINSWITH %@", "Photo \(n) of ")).firstMatch
    }

    // MARK: - Steps

    /// "New Collage" on the Collages screen; waits for the photos to be in.
    func newCollage(photos: Int = 6, file: StaticString = #filePath, line: UInt = #line) {
        tap(button("New collage"), file: file, line: line)
        wait("photos", is: photos, timeout: 60, file: file, line: line)
        waitIdle(file: file, line: line)
    }

    /// Opens a tab's panel: Images, Layout, Frames, Overlay or Looks.
    func openTab(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let index = ["Images", "Layout", "Frames", "Overlay", "Looks"].firstIndex(of: name)!
        tap(element("tab.\(name)"), file: file, line: line)
        wait("tab", is: index, file: file, line: line)
        wait("panel", is: 1, file: file, line: line)
    }

    /// Picks a filter by its key (as saved, e.g. "amber"); the first one
    /// shown when nil. Returns the key picked.
    @discardableResult
    func pickFilter(_ key: String? = nil, file: StaticString = #filePath, line: UInt = #line) -> String {
        openTab("Looks", file: file, line: line)
        let segment = app.segmentedControls.buttons["Filter"]
        if segment.exists && !segment.isSelected { segment.tap() }
        let tile: XCUIElement
        if let key {
            tile = element("filter.\(key)")
        } else {
            tile = app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier BEGINSWITH 'filter.' AND identifier != 'filter.none' AND identifier != %@",
                            "filter.\(state["filter"] ?? "")")).firstMatch
        }
        XCTAssertTrue(tile.waitForExistence(timeout: 10), "no filter tile · \(probeText)", file: file, line: line)
        let picked = String(tile.identifier.dropFirst("filter.".count))
        tile.tap()
        wait("filter", is: picked, file: file, line: line)
        return picked
    }

    /// Drags a slider's knob to a spot along it (0 = left end, 1 = right)
    /// like a finger does. (The app's sliders are drawn by hand, so
    /// XCUIElement.adjust doesn't reach them.)
    func drag(_ slider: XCUIElement, to position: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(slider.waitForExistence(timeout: 5), "no slider · \(probeText)", file: file, line: line)
        let from = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let to = slider.coordinate(withNormalizedOffset: CGVector(dx: position, dy: 0.5))
        from.press(forDuration: 0.1, thenDragTo: to)
    }

    /// Export → Export Options → Share; waits for the share sheet, then
    /// closes it (which clears the files).
    func exportAndShare(file: StaticString = #filePath, line: UInt = #line) {
        tap(button("Export"), file: file, line: line)
        XCTAssertTrue(app.navigationBars["Export Options"].waitForExistence(timeout: 5), file: file, line: line)
        tap(button("Share"), file: file, line: line)
        wait("exported", timeout: 60, file: file, line: line) { (Int($0) ?? 0) >= 1 }
        let share = app.otherElements["ActivityListView"]
        XCTAssertTrue(share.waitForExistence(timeout: 15), "no share sheet · \(probeText)", file: file, line: line)
        let close = share.buttons["Close"]
        if close.exists { close.tap() } else { app.swipeDown(velocity: .fast) }
        wait("exported", is: 0, timeout: 15, file: file, line: line)
    }

    /// Back to the Collages screen (the logo).
    func goToCollages(file: StaticString = #filePath, line: UInt = #line) {
        tap(button("Collages"), file: file, line: line)
        wait("photos", is: 0, file: file, line: line)
        XCTAssertTrue(button("New collage").waitForExistence(timeout: 10), file: file, line: line)
    }

    /// Lowers the panel (a tap on the canvas's empty top edge would hit
    /// the collage; the grabber's double tap puts it away).
    func closePanel() {
        if int("panel") == 1 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        }
    }
}
