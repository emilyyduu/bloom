//
//  Theme.swift
//  Bloom
//
//  Created by Emily Du on 31/10/2026.
//

import SwiftUI
import UIKit

// Bloom's design tokens. Every colour, text style, spacing value and
// corner radius in the app should come from here. If a view needs a
// value that isn't here, add a token rather than a one-off number.
//
// Brand palette (from the style guide):
//   Rose #D87A70, Red #C92E3E, Mustard #EEA316,
//   Green #588236, Blue #326B96, Brown #9E7C63
//
// Contrast rules (checked against the real backgrounds):
//   - White text is fine on Red, Blue and Green fills.
//   - Rose, Mustard and Brown fills always take dark ink text.
//   - Brand colours as TEXT on the background: only use the
//     `...Text` variants below, which clear 4.5:1 in both modes.
enum Theme {

    // MARK: - Helpers

    fileprivate static func hex(_ value: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    fileprivate static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? hex(dark) : hex(light)
        })
    }

    // MARK: - Brand palette (raw)
    // Use these for fills, illustrations and accents. For text, use
    // the role colours further down.

    enum Palette {
        static let rose    = dynamic(light: 0xD87A70, dark: 0xD87A70)
        static let red     = dynamic(light: 0xC92E3E, dark: 0xDF828B)
        static let mustard = dynamic(light: 0xEEA316, dark: 0xEEA316)
        static let green   = dynamic(light: 0x588236, dark: 0x9BB486)
        static let blue    = dynamic(light: 0x326B96, dark: 0x84A6C0)
        static let brown   = dynamic(light: 0x9E7C63, dark: 0x9E7C63)

        // Soft tinted card fills, like the pastel cards in the
        // references. Dark ink text sits on all of them.
        static let roseTint    = dynamic(light: 0xF9EAE8, dark: 0x4A3330)
        static let redTint     = dynamic(light: 0xF6DEE0, dark: 0x472326)
        static let mustardTint = dynamic(light: 0xFCF0DA, dark: 0x4D3B1D)
        static let greenTint   = dynamic(light: 0xE4EBDF, dark: 0x323A26)
        static let blueTint    = dynamic(light: 0xDEE7EE, dark: 0x2A343D)
        static let brownTint   = dynamic(light: 0xEFEAE6, dark: 0x3E352E)
    }

    // MARK: - Role colours
    // What views should actually reference.

    enum Colors {
        // Surfaces
        static let background   = dynamic(light: 0xFAF7F2, dark: 0x1C1A18) // warm off-white
        static let surface      = dynamic(light: 0xFFFFFF, dark: 0x2A2623) // cards
        static let surfaceMuted = dynamic(light: 0xF1ECE5, dark: 0x332F2B) // icon buttons, chips, inputs
        static let separator    = dynamic(light: 0xE6DFD6, dark: 0x3D3833)

        // Text
        static let textPrimary   = dynamic(light: 0x1F1B18, dark: 0xF3EFEA)
        static let textSecondary = dynamic(light: 0x6B625A, dark: 0xB3A99F)
        static let textOnColor   = Color.white // on red, blue, green fills only

        // Brand colours safe to use as text or icons on `background`
        static let greenText = dynamic(light: 0x4B6E2E, dark: 0x9BB486)
        static let redText   = dynamic(light: 0xC92E3E, dark: 0xDF828B)
        static let blueText  = dynamic(light: 0x326B96, dark: 0x84A6C0)

        // Actions
        static let actionFill   = dynamic(light: 0x588236, dark: 0x9BB486)
        static let onActionFill = dynamic(light: 0xFFFFFF, dark: 0x1C1A18)

        // Status
        static let error = dynamic(light: 0xC92E3E, dark: 0xFF8A80)

        // Shared Garden growth states
        static let blooming = greenText
        static let wilting  = dynamic(light: 0x8A5F0C, dark: 0xEEA316)
        static let dead     = dynamic(light: 0x6E5644, dark: 0xB3A99F)
    }

    // MARK: - Journal covers
    // Darkened brand shades so white titles clear 4.5:1 on every cover.

    enum Covers {
        static let palette: [Color] = [
            dynamic(light: 0x588236, dark: 0x5E8A3B), // Green
            dynamic(light: 0x326B96, dark: 0x3A759F), // Blue
            dynamic(light: 0xC92E3E, dark: 0xC93A49), // Red
            dynamic(light: 0x9C5851, dark: 0xA5615A), // Rose
            dynamic(light: 0x9B6A0E, dark: 0xA47314), // Mustard
            dynamic(light: 0x7E634F, dark: 0x876C57), // Brown
        ]

        static let names = ["Green", "Blue", "Red", "Rose", "Mustard", "Brown"]

        static func accent(_ index: Int) -> Color {
            palette[((index % palette.count) + palette.count) % palette.count]
        }

        static let text = Color.white
        static let spine = Color.black.opacity(0.22)
        static let shadow = Color.black.opacity(0.18)
        static let shade = Color.black
        static let shadeStrength = 0.65
    }

    // MARK: - Typography
    // One type scale. Headings use DM Sans, everything else uses SF Pro.
    // Sizes scale with Dynamic Type.
    //
    // Usage: Text("Today").textStyle(.title)

    enum Typeface {
        // DM Sans PostScript names (the 18pt static cut). If a font isn't
        // in the bundle (or isn't listed under UIAppFonts in Info.plist),
        // headings fall back to SF Pro at the same weight, so nothing breaks.
        static let regular = "DMSans18pt-Regular"
        static let medium = "DMSans18pt-Medium"
        static let semibold = "DMSans18pt-SemiBold"
        static let bold = "DMSans18pt-Bold"

        static func name(for weight: Font.Weight) -> String {
            switch weight {
            case .bold: bold
            case .semibold: semibold
            case .medium: medium
            default: regular
            }
        }
    }

    enum TextStyle {
        case display    // 34  big numbers, hero moments
        case title      // 28  screen titles
        case heading    // 22  section and card titles
        case subheading // 17  row titles, card labels (semibold)
        case body       // 17  reading text
        case callout    // 15  supporting text
        case caption    // 13  meta: dates, counts
        case label      // 12  tags and small labels

        var size: CGFloat {
            switch self {
            case .display: 34
            case .title: 28
            case .heading: 22
            case .subheading, .body: 17
            case .callout: 15
            case .caption: 13
            case .label: 12
            }
        }

        var relativeTo: Font.TextStyle {
            switch self {
            case .display: .largeTitle
            case .title: .title
            case .heading: .title2
            case .subheading: .headline
            case .body: .body
            case .callout: .callout
            case .caption: .footnote
            case .label: .caption
            }
        }

        var weight: Font.Weight {
            switch self {
            case .display, .title: .bold
            case .heading, .subheading, .label: .semibold
            case .body, .callout, .caption: .regular
            }
        }

        // Which styles use the heading typeface (DM Sans). The rest are SF Pro.
        var usesHeadingFace: Bool {
            switch self {
            case .display, .title, .heading: true
            default: false
            }
        }

        var tracking: CGFloat {
            switch self {
            case .display, .title: -0.4
            case .label: 0.3
            default: 0
            }
        }

        func font(scaledSize: CGFloat) -> Font {
            if usesHeadingFace {
                let name = Typeface.name(for: weight)
                if UIFont(name: name, size: scaledSize) != nil {
                    return .custom(name, fixedSize: scaledSize)
                }
            }
            return .system(size: scaledSize, weight: weight)
        }
    }

    // MARK: - Navigation bar
    // SwiftUI's .navigationTitle can't take a font, so the heading typeface
    // is applied to the inline title through UIKit. Call once at launch.

    @MainActor
    static func applyNavigationBarAppearance() {
        let style = TextStyle.heading
        let name = Typeface.name(for: style.weight)
        // Falls back to SF Pro when DM Sans isn't in the bundle.
        let base = UIFont(name: name, size: style.size)
            ?? UIFont.systemFont(ofSize: style.size, weight: .semibold)
        let font = UIFontMetrics(forTextStyle: .title2).scaledFont(for: base)

        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.titleTextAttributes = [.font: font]

        let bar = UINavigationBar.appearance()
        bar.standardAppearance = appearance
        bar.compactAppearance = appearance
        bar.scrollEdgeAppearance = appearance
        bar.compactScrollEdgeAppearance = appearance
    }

    // MARK: - Spacing

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let screenEdge: CGFloat = 20
    }

    // MARK: - Corner radius
    // Three values only. Use Capsule() for pills and buttons.

    enum Radius {
        static let small: CGFloat = 12  // inputs, chips, thumbnails
        static let card: CGFloat = 20   // cards
        static let large: CGFloat = 28  // hero cards, sheets
    }
}

// MARK: - View modifiers

private struct BloomTextModifier: ViewModifier {
    let style: Theme.TextStyle
    @ScaledMetric private var size: CGFloat

    init(style: Theme.TextStyle) {
        self.style = style
        _size = ScaledMetric(wrappedValue: style.size, relativeTo: style.relativeTo)
    }

    func body(content: Content) -> some View {
        content
            .font(style.font(scaledSize: size))
            .tracking(style.tracking)
    }
}

private struct CardModifier: ViewModifier {
    let fill: Color
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(Theme.Spacing.lg)
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func textStyle(_ style: Theme.TextStyle) -> some View {
        modifier(BloomTextModifier(style: style))
    }

    // White (or dark surface) card. Pass a Palette tint for coloured cards.
    func card(_ fill: Color = Theme.Colors.surface, radius: CGFloat = Theme.Radius.card) -> some View {
        modifier(CardModifier(fill: fill, radius: radius))
    }
}

// MARK: - Button styles

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textStyle(.subheading)
            .foregroundStyle(Theme.Colors.onActionFill)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Theme.Colors.actionFill, in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : (isEnabled ? 1 : 0.5))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textStyle(.subheading)
            .foregroundStyle(Theme.Colors.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Theme.Colors.surfaceMuted, in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : (isEnabled ? 1 : 0.5))
    }
}

// The round icon buttons from the references (back, bell, search).
struct CircleIconButtonStyle: ButtonStyle {
    var fill: Color = Theme.Colors.surface

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(Theme.Colors.textPrimary)
            .frame(width: 44, height: 44)
            .background(fill, in: Circle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var bloomPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var bloomSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

extension ButtonStyle where Self == CircleIconButtonStyle {
    static var bloomCircle: CircleIconButtonStyle { CircleIconButtonStyle() }
}

#Preview("Tokens") {
    ScrollView {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            Text("Today").textStyle(.title)
            Text("Your garden").textStyle(.heading)

            HStack(spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Streak").textStyle(.callout).foregroundStyle(Theme.Colors.textSecondary)
                    Text("12").textStyle(.display)
                    Text("days").textStyle(.caption).foregroundStyle(Theme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(Theme.Palette.greenTint)

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Notes").textStyle(.callout).foregroundStyle(Theme.Colors.textSecondary)
                    Text("4").textStyle(.display)
                    Text("this week").textStyle(.caption).foregroundStyle(Theme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }

            Text("A short note body so you can see reading text at size.")
                .textStyle(.body)
                .card()

            Button("Write a note") {}.buttonStyle(.bloomPrimary)
            Button("Not now") {}.buttonStyle(.bloomSecondary)
            Button { } label: { Image(systemName: "bell") }.buttonStyle(.bloomCircle)
        }
        .foregroundStyle(Theme.Colors.textPrimary)
        .padding(Theme.Spacing.screenEdge)
    }
    .background(Theme.Colors.background)
}
