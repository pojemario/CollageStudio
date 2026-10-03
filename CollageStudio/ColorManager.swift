import SwiftUI

/// The one button look used across the app: rounded rects with this corner
/// radius, either prominent (accent fill, white content) or secondary
/// (system fill, primary content, hairline).
public enum ButtonStyleGuide {
    public static let cornerRadius: CGFloat = 10
}

extension View {
    /// Background + hairline for a button label in the app's button style.
    func appButtonBackground(prominent: Bool, radius: CGFloat = ButtonStyleGuide.cornerRadius) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background(shape.fill(prominent ? Color.accentColor : ColorManager.systemFill))
            .overlay(shape.strokeBorder(Color.primary.opacity(prominent ? 0 : 0.18), lineWidth: 1))
    }
}

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
    
    /// Main application background: a soft cool gray (near-black in dark
    /// mode), so the collage canvas and the floating glass chrome read as
    /// layered pieces on top.
    public static var canvasAreaBackground: Color {
        adaptive(light: (0.945, 0.947, 0.96, 1), dark: (0.075, 0.075, 0.085, 1))
    }

    /// Hairline around the floating glass pieces: a bright rim in light
    /// mode, a faint one in dark mode.
    public static var glassStroke: Color {
        adaptive(light: (1, 1, 1, 0.6), dark: (1, 1, 1, 0.12))
    }

    /// One color per appearance, resolved by the system.
    private static func adaptive(light: (Double, Double, Double, Double),
                                 dark: (Double, Double, Double, Double)) -> Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: c.3)
        })
        #else
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: c.3)
        })
        #endif
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
