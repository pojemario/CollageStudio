import SwiftUI
#if os(macOS)
import AppKit
#endif

// MARK: - Cursor modifier (macOS only)

extension View {
    @ViewBuilder
    func cursor(_ cursor: CustomCursor) -> some View {
        #if os(macOS)
        self.onHover { inside in
            if inside {
                switch cursor {
                case .resizeUpDown:    NSCursor.resizeUpDown.push()
                case .resizeLeftRight: NSCursor.resizeLeftRight.push()
                }
            } else {
                NSCursor.pop()
            }
        }
        #else
        self
        #endif
    }
}

enum CustomCursor { case resizeUpDown, resizeLeftRight }
