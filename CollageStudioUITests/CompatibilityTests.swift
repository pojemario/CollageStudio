import XCTest

/// Collages saved by earlier builds (the ones testers have) still open,
/// whole and as they were, in this build. The saved collages are in
/// Fixtures/build<N>/, made by that build (photos scaled down after).
/// A new build with a changed save format: add its collages there too.
final class CompatibilityTests: CollageUITestCase {

    private struct Expected {
        let build: Int
        let photos: Int
        let pages: Int
        let filter: String
    }

    /// Every saved collage in Fixtures, by its id.
    private let fixtures: [String: Expected] = [
        "F461C42B-9BC5-485D-8F5D-EFA044FCA668": Expected(build: 70, photos: 3, pages: 1, filter: "none"),
        "C2488861-E1FD-4EEB-A18B-31F0C3E9456C": Expected(build: 82, photos: 5, pages: 2, filter: "classicNegative"),
        "FADDC700-A3A8-44AE-A2FD-DC3DE8A5420B": Expected(build: 82, photos: 3, pages: 1, filter: "none"),
        "4B520F10-05DE-4A33-9D2C-7E06CF900A54": Expected(build: 86, photos: 5, pages: 2, filter: "classicNegative"),
        "CDADC4AF-9761-453D-998B-E2A741BB731B": Expected(build: 86, photos: 3, pages: 1, filter: "none"),
        "9425C55A-AB58-4659-98DD-695DF8624B7C": Expected(build: 106, photos: 5, pages: 2, filter: "classicNegative"),
        "9EA695A8-0F97-4831-8968-DDB952F4D8B9": Expected(build: 106, photos: 3, pages: 1, filter: "none"),
    ]

    func testCollagesFromEarlierBuildsOpen() {
        launch(extra: ["-uiTestFixtures"])
        wait("collages", is: fixtures.count)
        checkAll()

        // Opened (and saved again) by this build, they open again after
        // the app is closed.
        app.terminate()
        launch(keepData: true)
        wait("collages", is: fixtures.count)
        checkAll()
    }

    func testCollageFromOldestBuildExports() {
        launch(extra: ["-uiTestFixtures"])
        wait("collages", is: fixtures.count)
        let oldest = fixtures.min { $0.value.build < $1.value.build }!
        open(oldest.key, oldest.value)
        exportAndShare()
    }

    private func checkAll() {
        for (id, expected) in fixtures.sorted(by: { $0.value.build < $1.value.build }) {
            open(id, expected)
            goToCollages()
        }
    }

    private func open(_ id: String, _ expected: Expected, file: StaticString = #filePath, line: UInt = #line) {
        let tile = app.buttons["collage.\(id)"]
        // The list is lazy: scroll until the tile is made.
        for _ in 0..<6 where !tile.exists || !tile.isHittable {
            app.swipeUp()
        }
        for _ in 0..<6 where !tile.exists || !tile.isHittable {
            app.swipeDown()
        }
        XCTAssertTrue(tile.waitForExistence(timeout: 5), "build \(expected.build) collage \(id) isn't in the list",
                      file: file, line: line)
        tile.tap()
        wait("photos", is: expected.photos, timeout: 30, file: file, line: line)
        waitIdle(file: file, line: line)
        XCTAssertEqual(int("unloaded"), 0, "build \(expected.build): photos didn't load · \(probeText)", file: file, line: line)
        XCTAssertEqual(int("pages"), expected.pages, "build \(expected.build) · \(probeText)", file: file, line: line)
        XCTAssertEqual(state["filter"], expected.filter, "build \(expected.build) · \(probeText)", file: file, line: line)
    }
}
