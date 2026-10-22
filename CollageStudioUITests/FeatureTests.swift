import XCTest

/// The changes from the 2026-10-22 review: Save to Photos, Cancel while
/// exporting, All Pages, the panel's Reset, 3:4, Export from the Collages
/// screen, and saying when a save fails.
final class FeatureTests: CollageUITestCase {

    func testSaveToPhotos() {
        // iOS asks once whether the app may add photos.
        addUIInterruptionMonitor(withDescription: "Photos access") { alert in
            for label in ["Allow Full Access", "Allow Access", "Allow", "OK"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        launch(photos: 3)
        newCollage(photos: 3)
        tap(button("Export"))
        XCTAssertTrue(app.navigationBars["Export Options"].waitForExistence(timeout: 5))
        tap(button("Save to Photos"))
        // The permission alert (first time only) belongs to the system.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.alerts.firstMatch.waitForExistence(timeout: 3) {
            for label in ["Allow Full Access", "Allow Access", "Allow", "OK"] where springboard.alerts.buttons[label].exists {
                springboard.alerts.buttons[label].tap()
                break
            }
        }
        // One page, one post.
        wait("savedtophotos", is: 1, timeout: 30)
        XCTAssertEqual(int("exported"), 0, "files left after saving")
        XCTAssertFalse(app.otherElements["ActivityListView"].exists, "the share sheet opened")
    }

    func testCancelExport() {
        launch(photos: 12, extra: ["-uiTestSlowExport"])
        newCollage(photos: 12)
        tap(button("Export"))
        XCTAssertTrue(app.navigationBars["Export Options"].waitForExistence(timeout: 5))
        // All posts (the collage made two pages).
        let all = app.segmentedControls.buttons.matching(NSPredicate(format: "label BEGINSWITH 'All'")).firstMatch
        if all.exists { all.tap() }
        tap(button("Share"))
        wait("exporting", is: 1, timeout: 10)
        tap(button("Cancel"))
        wait("exporting", is: 0, timeout: 15)
        XCTAssertEqual(int("exported"), 0)
        XCTAssertFalse(app.otherElements["ActivityListView"].waitForExistence(timeout: 3), "share sheet after Cancel")
    }

    func testApplyLooksToAllPages() {
        launch(photos: 12)
        newCollage(photos: 12)
        wait("pages") { (Int($0) ?? 0) >= 2 }
        let filter = pickFilter()
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Apply Looks settings'")).firstMatch)
        wait("toast") { $0.hasPrefix("Applied") }
        tap(button("Next post"))
        wait("page", is: 1)
        wait("filter", is: filter)
    }

    func testPanelResetPutsSlidersBack() {
        launch(photos: 3)
        newCollage(photos: 3)
        openTab("Looks")
        tap(app.segmentedControls.buttons["Edit"])
        drag(app.sliders["Exposure"], to: 0.85)
        wait("edits", is: 1)
        tap(button("Reset these settings"))
        wait("edits", is: 0)
    }

    func testThreeByFourCanvas() {
        launch(photos: 3)
        newCollage(photos: 3)
        tap(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Canvas ratio'")).firstMatch)
        tap(button("3×4"))
        wait("ratio", is: "3:4")
    }

    func testExportFromCollagesScreen() {
        launch(photos: 3)
        newCollage(photos: 3)
        goToCollages()
        wait("collages", is: 1)
        collageTiles.firstMatch.press(forDuration: 1.0)
        tap(button("Export…"))
        XCTAssertTrue(app.navigationBars["Export Options"].waitForExistence(timeout: 15), "no Export Options · \(probeText)")
        XCTAssertEqual(int("photos"), 3)
    }

    func testFailedSaveIsShown() {
        launch(photos: 3, extra: ["-uiTestFailSaves"])
        newCollage(photos: 3)
        pickFilter()
        wait("savefailed", is: 1, timeout: 15)
        XCTAssertTrue(app.staticTexts["Couldn't save this collage"].waitForExistence(timeout: 5))
        tap(button("Retry"))
        // Still failing: the banner stays.
        sleep(2)
        XCTAssertEqual(int("savefailed"), 1)
    }
}
