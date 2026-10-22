import XCTest

/// What only a real phone can check: subject lifting (Vision) doesn't run
/// in the simulator. Skipped there.
final class DeviceTests: CollageUITestCase {

    override func setUpWithError() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("needs a device (subject lifting doesn't run in the simulator)")
        #else
        try super.setUpWithError()
        #endif
    }

    func testCutoutFindsSubjectAndExports() {
        launch(photos: 3, extra: ["-uiTestSubject"])
        newCollage(photos: 3)
        closePanel()
        tap(photo(1))
        wait("selected", is: 1)
        tap(button("Cutout"))
        wait("cutoutedit", is: 1)
        // The subject is found and the photo breaks out of its box.
        wait("subject", is: 1, timeout: 30)
        wait("cutouts", is: 1, timeout: 10)

        // Leaving Cutout keeps it.
        openTab("Images")
        wait("cutoutedit", is: 0)
        XCTAssertEqual(int("cutouts"), 1)

        // It renders in an export.
        exportAndShare()

        // And comes back with the collage.
        goToCollages()
        app.terminate()
        launch(keepData: true)
        tap(collageTiles.firstMatch)
        wait("photos", is: 3, timeout: 30)
        wait("cutouts", is: 1, timeout: 10)
    }
}
