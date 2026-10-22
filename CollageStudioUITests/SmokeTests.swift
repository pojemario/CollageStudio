import XCTest

/// The main paths through the app, as a person would take them. Run with
/// Tools/uitest.sh (the simulator by default).
final class SmokeTests: CollageUITestCase {

    func testNewCollageShowsItsPhotos() {
        launch()
        newCollage()
        XCTAssertTrue(photo(1).waitForExistence(timeout: 10), "no photo boxes · \(probeText)")
        XCTAssertEqual(int("pages"), 1)
        // A new collage opens on the Images panel.
        wait("panel", is: 1)
        wait("tab", is: 0)
    }

    func testEveryTabOpens() {
        launch()
        newCollage()
        for tab in ["Layout", "Frames", "Overlay", "Looks", "Images"] {
            openTab(tab)
        }
    }

    func testFilterStrengthUndoRedo() {
        launch()
        newCollage()
        let first = pickFilter()
        wait("strength", is: 100)

        drag(app.sliders["Strength"], to: 0.15)
        wait("strength") { (Int($0) ?? 100) < 80 }

        let second = pickFilter()
        XCTAssertNotEqual(first, second)

        // Undo goes back to the first filter, Redo forward again.
        wait("undo", is: 1)
        tap(button("Undo"))
        wait("filter", is: first)
        wait("redo", is: 1)
        tap(button("Redo"))
        wait("filter", is: second)

        // None turns it off.
        pickFilter("none")
    }

    func testPhotoToolsEditAndRemove() {
        launch()
        newCollage()
        closePanel()
        tap(photo(2))
        wait("selected", is: 1)

        tap(button("Edit"))
        wait("photoedit", is: 1)
        // Any tab leaves the photo editor.
        openTab("Looks")
        wait("photoedit", is: 0)
        closePanel()

        tap(photo(1))
        wait("selected", is: 1)
        tap(button("Remove"))
        wait("photos", is: 5)
        wait("selected", is: 0)
    }

    func testMovePhotoToNewPageAndStepPosts() {
        launch()
        newCollage()
        closePanel()
        tap(photo(6))
        wait("selected", is: 1)
        tap(button("Move"))
        tap(button("New Page"))
        wait("pages", is: 2)
        wait("posts", is: 2)

        tap(button("Next post"))
        wait("post", is: 1)
        tap(button("Previous post"))
        wait("post", is: 0)
    }

    func testFullScreenSwipeAndTap() {
        launch()
        newCollage()
        closePanel()
        // Two posts to swipe between.
        tap(photo(6))
        tap(button("Move"))
        tap(button("New Page"))
        wait("posts", is: 2)
        wait("post", is: 0)

        tap(button("Full screen"))
        wait("fullscreen", is: 1)
        XCTAssertFalse(button("Export").exists, "the toolbar still shows in full screen")

        let screen = element("Exit full screen")
        XCTAssertTrue(screen.waitForExistence(timeout: 5))
        screen.swipeLeft()
        wait("post", is: 1)
        screen.swipeRight()
        wait("post", is: 0)
        // Still full screen after swiping; a tap goes back.
        XCTAssertEqual(int("fullscreen"), 1)
        screen.tap()
        wait("fullscreen", is: 0)
        XCTAssertTrue(button("Export").waitForExistence(timeout: 5))
    }

    func testExportOpensShareSheet() {
        launch()
        newCollage()
        pickFilter()
        // Files made, the share sheet, and closing it clears the files.
        exportAndShare()
        waitIdle()
    }

    func testCollageIsSavedAndReopens() {
        launch()
        newCollage()
        let filter = pickFilter()
        goToCollages()
        wait("collages", is: 1)
        XCTAssertTrue(collageTiles.firstMatch.label.hasSuffix("6 photos"), collageTiles.firstMatch.label)

        // Comes back after the app is closed and opened again.
        app.terminate()
        launch(keepData: true)
        wait("collages", is: 1)
        tap(collageTiles.firstMatch)
        wait("photos", is: 6, timeout: 30)
        wait("filter", is: filter)
        waitIdle()
    }

    func testSavedWhenAppGoesToBackground() {
        launch()
        newCollage()
        pickFilter()
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.terminate()
        launch(keepData: true)
        wait("collages", is: 1)
    }

    func testRenameDuplicateAndRemoveCollages() {
        launch(photos: 3)
        newCollage(photos: 3)
        goToCollages()
        wait("collages", is: 1)

        // Rename.
        let tile = collageTiles.firstMatch
        tile.press(forDuration: 1.0)
        tap(button("Rename"))
        let field = app.alerts["Rename"].textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        // It opens empty (the current name shown in it): typing replaces it.
        field.tap()
        field.typeText("Holiday Test")
        tap(app.alerts["Rename"].buttons["Save"])
        XCTAssertTrue(app.buttons["Holiday Test, 3 photos"].waitForExistence(timeout: 10),
                      "renamed tile not found: \(collageTiles.allElementsBoundByIndex.map(\.label))")

        // Duplicate, twice.
        for n in 2...3 {
            collageTiles.firstMatch.press(forDuration: 1.0)
            tap(button("Duplicate"))
            wait("collages", is: n)
        }

        // Select all and remove them together.
        tap(button("Select"))
        tap(button("Select All"))
        tap(button("Remove 3"))
        let confirm = app.sheets.buttons["Remove 3"].exists ? app.sheets.buttons["Remove 3"] : app.buttons["Remove 3"].firstMatch
        tap(confirm)
        wait("collages", is: 0, timeout: 15)
    }

    /// Many quick edits in a row: the app keeps up (no hang) and its memory
    /// stays within bounds.
    func testManyQuickEditsStayResponsive() {
        launch(photos: 12)
        newCollage(photos: 12)
        var peak = 0
        for round in 0..<8 {
            pickFilter()
            drag(app.sliders["Strength"], to: CGFloat(round % 4) / 4 + 0.1)
            openTab(["Layout", "Frames", "Overlay", "Images"][round % 4])
            peak = max(peak, int("mem"))
        }
        // Every step above waited on the app; now it settles.
        waitIdle(timeout: 30)
        peak = max(peak, int("mem"))
        let note = XCTAttachment(string: "peak memory \(peak) MB · \(probeText)")
        note.lifetime = .keepAlways
        add(note)
        XCTAssertLessThan(peak, 900, "memory peaked at \(peak) MB")
    }
}
