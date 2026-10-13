import SwiftUI
import UIKit

// Bloom's brand colours, each defined once with explicit light and
// dark values via a dynamic UIColor provider, so dark mode needs no
// asset catalog entries. Everything else in the app uses the system's
// own semantic colours directly (Color(.systemBackground), .label,
// .secondary, .separator, and so on); only genuinely Bloom-specific
// colours live here.
//
// Every value below was chosen and verified against its real
// background (see the Week-whatever dark mode audit) to clear at
// least a 3:1 contrast ratio in both appearances, the WCAG AA bar for
// icons and other non-text UI components.
enum Theme {
    enum Colors {
        // The growth states in the Shared Circle Garden. Each is a
        // dedicated colour rather than a reused system colour (.green,
        // .gray) because the system colours read fine on their own but
        // fail contrast against the pale circle they sit on in light
        // mode (as low as 1.78:1); these were tuned against that exact
        // background in both modes instead.
        static let blooming = Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.45, green: 0.85, blue: 0.48, alpha: 1)
                : UIColor(red: 0.08, green: 0.42, blue: 0.14, alpha: 1)
        })

        static let wilting = Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.80, green: 0.65, blue: 0.30, alpha: 1)
                : UIColor(red: 0.47, green: 0.36, blue: 0.05, alpha: 1)
        })

        static let dead = Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.65, green: 0.65, blue: 0.65, alpha: 1)
                : UIColor(red: 0.35, green: 0.35, blue: 0.35, alpha: 1)
        })

        // The future 3D garden's placeholder card. A soft soil green in
        // light mode, a deep forest green in dark mode; the leaf icon
        // on top reuses `blooming`, which was independently verified
        // against this exact background too.
        static let gardenCardBackground = Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.07, green: 0.15, blue: 0.09, alpha: 1)
                : UIColor(red: 0.86, green: 0.92, blue: 0.85, alpha: 1)
        })
    }

    enum Fonts {
        // The large root-screen title ScreenHeader shows on Home,
        // Journal, Greenhouse and Profile. One definition here so every
        // screen stays in sync if it ever changes.
        static let screenTitle: Font = .largeTitle.bold()

        // Used by ScreenHeader instead of screenTitle when the vertical
        // size class is compact (landscape on iPhone), where a full
        // large title would eat too much of the limited height.
        static let screenTitleCompact: Font = .title2.bold()

        // Bloom doesn't ship a custom font today, but a future one
        // should be added through here rather than a fixed
        // .font(.custom(name, size:)) anywhere else, so it keeps
        // scaling with Dynamic Type via `relativeTo:` and falls back to
        // the system font at the same text style if it isn't actually
        // installed (e.g. missing from the target, or not yet added to
        // Info.plist's UIAppFonts).
        static func custom(_ name: String, textStyle: Font.TextStyle) -> Font {
            let uiStyle = uiFontTextStyle(for: textStyle)
            let baseSize = UIFont.preferredFont(forTextStyle: uiStyle).pointSize
            guard UIFont(name: name, size: baseSize) != nil else {
                return .system(textStyle)
            }
            return .custom(name, size: baseSize, relativeTo: textStyle)
        }

        private static func uiFontTextStyle(for textStyle: Font.TextStyle) -> UIFont.TextStyle {
            switch textStyle {
            case .largeTitle: return .largeTitle
            case .title: return .title1
            case .title2: return .title2
            case .title3: return .title3
            case .headline: return .headline
            case .subheadline: return .subheadline
            case .body: return .body
            case .callout: return .callout
            case .footnote: return .footnote
            case .caption: return .caption1
            case .caption2: return .caption2
            default: return .body
            }
        }
    }
}
