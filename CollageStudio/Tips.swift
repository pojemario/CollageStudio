import SwiftUI
import TipKit

/// First-run hints for gestures that can't be seen, shown one after another
/// (each waits until the one before it is dismissed or acted on).
enum CollageTips {
    /// How far through the sequence the user is.
    @Parameter static var step: Int = 0
    /// Tips only make sense once there's a collage.
    @Parameter static var hasImages: Bool = false

    /// TipKit set up once at launch (`-resetTips` starts them over).
    static func configure() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-resetTips") { try? Tips.resetDatastore() }
        #endif
        try? Tips.configure([.displayFrequency(.immediate)])
    }

    /// Moves the sequence on as each tip goes away.
    static func follow() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await advance(after: TabBarTip(), to: 1) }
            group.addTask { await advance(after: PhotoMenuTip(), to: 2) }
            group.addTask { await advance(after: ResetSwipeTip(), to: 3) }
        }
    }

    private static func advance(after tip: some Tip, to next: Int) async {
        for await status in tip.statusUpdates {
            if case .invalidated = status {
                await MainActor.run { if step < next { step = next } }
                return
            }
        }
    }
}

struct TabBarTip: Tip {
    var title: Text { Text("Slide along the tabs") }
    var message: Text? { Text("Drag your finger across the tab bar to jump between tools.") }
    var image: Image? { Image(systemName: "hand.point.up.left") }
    var rules: [Rule] {
        #Rule(CollageTips.$hasImages) { $0 == true }
        #Rule(CollageTips.$step) { $0 == 0 }
    }
}

struct PhotoMenuTip: Tip {
    var title: Text { Text("Touch and hold a photo") }
    var message: Text? { Text("For Protrude, Replace, Move and Remove. Hold and drag it onto another photo to swap them.") }
    var image: Image? { Image(systemName: "hand.tap") }
    var rules: [Rule] {
        #Rule(CollageTips.$step) { $0 == 1 }
    }
}

struct ResetSwipeTip: Tip {
    var title: Text { Text("Swipe the numbers to reset") }
    var message: Text? { Text("Swipe up or down over the labels or numbers to reset these sliders. Double-tap one to reset just it.") }
    var image: Image? { Image(systemName: "arrow.up.arrow.down") }
    var rules: [Rule] {
        #Rule(CollageTips.$step) { $0 == 2 }
    }
}
