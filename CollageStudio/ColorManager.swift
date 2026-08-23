import SwiftUI

public enum ColorManager {
    /// The grouped background color used in grouped interface styles.
    public static var groupedBackground: Color {
        #if canImport(UIKit)
        return Color(uiColor: .systemGroupedBackground)
        #elseif canImport(AppKit)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color(.sRGB, red: 0.94, green: 0.94, blue: 0.96, opacity: 1)
        #endif
    }
    
    /// The window background color used for main window backgrounds.
    public static var windowBackground: Color {
        #if canImport(AppKit)
        return Color(nsColor: .windowBackgroundColor)
        #elseif canImport(UIKit)
        return Color(uiColor: .systemBackground)
        #else
        return Color.white
        #endif
    }
    
    /// The system fill color used for fill elements.
    public static var systemFill: Color {
        #if canImport(UIKit)
        return Color(uiColor: .systemFill)
        #elseif canImport(AppKit)
        return Color.black.opacity(0.1)
        #else
        return Color.gray.opacity(0.2)
        #endif
    }
    
    /// Main application background — a soft warm cream (RGB 240,230,210).
    public static var canvasAreaBackground: Color {
        Color(.sRGB, red: 240.0 / 255.0, green: 230.0 / 255.0, blue: 210.0 / 255.0, opacity: 1)
    }

    /// Canvas background shown before any images are added. Adapts to
    /// light/dark mode, unlike the user-chosen collage background color.
    public static var emptyCanvasBackground: Color {
        #if canImport(UIKit)
        return Color(uiColor: .secondarySystemGroupedBackground)
        #elseif canImport(AppKit)
        return Color(nsColor: .underPageBackgroundColor)
        #else
        return Color.gray.opacity(0.15)
        #endif
    }

    /// The system background color used for general backgrounds.
    public static var systemBackground: Color {
        #if canImport(UIKit)
        return Color(uiColor: .systemBackground)
        #elseif canImport(AppKit)
        return Color(nsColor: .windowBackgroundColor)
        #else
        return Color.white
        #endif
    }
}
