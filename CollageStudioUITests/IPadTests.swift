import XCTest

/// The iPad: held upright it works like the phone (tab bar and panel at
/// the bottom); held sideways the controls are a sidebar of sections, one
/// open at a time, and a selected photo's tools float at the bottom of the
/// canvas; leaving the photo closes them all. Skipped on
/// a phone: `zsh Tools/uitest.sh -device <iPad simulator> -only IPadTests`.
final class IPadTests: CollageUITestCase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad only") }
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        try super.tearDownWithError()
        XCUIDevice.shared.orientation = .portrait
    }

    private func section(_ title: String) -> XCUIElement { element("section.\(title)") }

    private func isOpen(_ title: String) -> Bool { section(title).isSelected }

    /// A picture of the screen in the results, to look over.
    private func snapshot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testUprightIsLikeThePhone() {
        launch()
        newCollage()
        XCTAssertTrue(element("tab.Layout").waitForExistence(timeout: 5), "no tab bar upright")
        XCTAssertFalse(section("Layout").exists, "a sidebar upright")
        openTab("Layout")
        closePanel()
        tap(photo(1))
        wait("selected", is: 1)
        XCTAssertTrue(button("Edit").waitForExistence(timeout: 5))
        snapshot("upright-photo-tools")
    }

    func testSidewaysSidebarOpensOneSectionAtATime() {
        XCUIDevice.shared.orientation = .landscapeLeft
        launch()
        newCollage()
        XCTAssertTrue(section("Canvas Ratio").waitForExistence(timeout: 5), "no sidebar sideways")
        XCTAssertFalse(element("tab.Layout").exists, "a tab bar sideways")

        // First launch: Images open.
        XCTAssertTrue(isOpen("Images"))
        XCTAssertFalse(isOpen("Canvas Ratio"))

        // Opening a section closes the other, Canvas Ratio too.
        tap(section("Layout"))
        XCTAssertTrue(isOpen("Layout"))
        XCTAssertFalse(isOpen("Images"))
        snapshot("sideways-layout")
        tap(section("Canvas Ratio"))
        XCTAssertTrue(isOpen("Canvas Ratio"))
        XCTAssertFalse(isOpen("Layout"))
        tap(section("Looks"))
        XCTAssertTrue(isOpen("Looks"))
        XCTAssertFalse(isOpen("Canvas Ratio"))

        // The open one closes when tapped: none open.
        tap(section("Looks"))
        XCTAssertFalse(isOpen("Looks"))

        // A selected photo's tools float at the bottom of the canvas.
        tap(photo(1))
        wait("selected", is: 1)
        snapshot("sideways-photo-tools")
        tap(button("Edit"))
        wait("photoedit", is: 1)
        // Its editor is the open section.
        XCTAssertTrue(section("Edit Photo").waitForExistence(timeout: 5))
        XCTAssertTrue(isOpen("Edit Photo"))
        snapshot("sideways-edit-photo")
        // Another section ends the editing.
        tap(section("Frames"))
        wait("photoedit", is: 0)
        XCTAssertTrue(isOpen("Frames"))
        XCTAssertFalse(section("Edit Photo").exists)

        // Leaving the photo (a tap beside the collage) ends its editing
        // and closes every section.
        tap(button("Edit"))
        wait("photoedit", is: 1)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5)).tap()
        wait("selected", is: 0)
        wait("photoedit", is: 0)
        XCTAssertFalse(section("Edit Photo").exists)
        for title in ["Canvas Ratio", "Images", "Layout", "Frames", "Overlay", "Looks"] {
            XCTAssertFalse(isOpen(title), "\(title) stayed open")
        }

        // So does Close on the photo's tools.
        tap(section("Looks"))
        tap(photo(1))
        wait("selected", is: 1)
        tap(button("Close"))
        wait("selected", is: 0)
        XCTAssertFalse(isOpen("Looks"))

        // Remembered when the app opens again.
        tap(section("Layout"))
        app.terminate()
        launch(keepData: true)
        tap(collageTiles.firstMatch)
        wait("photos", is: 6, timeout: 30)
        XCTAssertTrue(section("Layout").waitForExistence(timeout: 5))
        XCTAssertTrue(isOpen("Layout"))
    }
}
