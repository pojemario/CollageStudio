import XCTest

/// A long, busy session: collage after collage with filters, sliders, every
/// tab, undo / redo, export, back to Collages and reopening. The app must
/// stay up and responsive, and its memory on the idle Collages screen must
/// not keep climbing from cycle to cycle (what a leak looks like).
final class StressTests: CollageUITestCase {

    func testLongBusySessionStaysUpAndDoesNotLeak() {
        let photos = 16
        launch(photos: photos)
        var peak = 0
        var idleMemory: [Int] = []
        let tabs = ["Layout", "Frame", "Overlays", "Content", "Style"]

        for cycle in 0..<5 {
            newCollage(photos: photos)
            for round in 0..<6 {
                pickFilter()
                drag(app.sliders["Strength"], to: CGFloat((round + cycle) % 5) / 5 + 0.1)
                openTab(tabs[(round + cycle) % tabs.count])
                peak = max(peak, int("mem"))
            }
            // Undo / redo a few steps.
            for _ in 0..<3 where button("Undo").exists && button("Undo").isEnabled { button("Undo").tap() }
            for _ in 0..<2 where button("Redo").exists && button("Redo").isEnabled { button("Redo").tap() }
            waitIdle(timeout: 30)
            // (Overlay mode hides the toolbar's Export: leave it first.)
            openTab("Content")
            exportAndShare()
            waitIdle(timeout: 30)
            peak = max(peak, int("mem"))

            // Back to Collages, open the newest again, back once more.
            goToCollages()
            wait("collages", is: cycle + 1, timeout: 15)
            tap(collageTiles.firstMatch)
            wait("photos", is: photos, timeout: 60)
            waitIdle(timeout: 30)
            peak = max(peak, int("mem"))
            goToCollages()

            // Settled on the Collages screen: the memory to compare.
            sleep(3)
            idleMemory.append(int("mem"))
        }

        let note = XCTAttachment(string: "peak \(peak) MB · idle per cycle \(idleMemory) MB · \(probeText)")
        note.name = "memory"
        note.lifetime = .keepAlways
        add(note)
        print("STRESS memory: peak \(peak) MB, idle per cycle \(idleMemory) MB")

        XCTAssertLessThan(peak, 1200, "memory peaked at \(peak) MB")
        // After the first cycle's caches are warm, idle memory may wander but
        // must not keep growing.
        if let second = idleMemory.dropFirst().first, let last = idleMemory.last {
            XCTAssertLessThan(last - second, 150, "idle memory grew \(second) → \(last) MB over the session")
        }
    }
}
