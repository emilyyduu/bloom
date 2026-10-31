import SwiftUI

// A journal as a book: a portrait cover (3 by 4) with a darker spine down
// the left edge, rounded more on the right than the left, and a soft
// shadow. Without a photo it is a theme colour with a small leaf. With a
// photo the photo fills the cover and a dark gradient sits behind the title,
// so white text stays readable even over a very bright photo.
//
// The cover is decoration: the button that holds it carries the label for
// VoiceOver, so the cover (and any photo on it) is hidden from it.
struct BookCoverView: View {
    let title: String
    let subtitle: String
    var coverImage: UIImage?
    let accent: Color
    // Smaller type for the month books.
    var isCompact = false
    // Off for the small thumbnail in a list row.
    var showsText = true

    private static let spineFraction: CGFloat = 0.12

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 4,
            bottomLeadingRadius: 4,
            bottomTrailingRadius: 14,
            topTrailingRadius: 14,
            style: .continuous
        )
    }

    var body: some View {
        Color.clear
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay {
                GeometryReader { proxy in
                    cover(size: proxy.size)
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.Colors.separator, lineWidth: 0.5))
            .shadow(color: Theme.Covers.shadow, radius: 6, x: 2, y: 4)
            .accessibilityHidden(true)
    }

    private func cover(size: CGSize) -> some View {
        let spine = size.width * Self.spineFraction
        return ZStack(alignment: .bottomLeading) {
            if let coverImage {
                Image(uiImage: coverImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                LinearGradient(
                    stops: [
                        .init(color: Theme.Covers.shade.opacity(0), location: 0.35),
                        .init(color: Theme.Covers.shade.opacity(Theme.Covers.shadeStrength), location: 0.55),
                        .init(color: Theme.Covers.shade.opacity(0.85), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            } else {
                accent
                Image(systemName: "leaf.fill")
                    .textStyle(isCompact ? .caption : .body)
                    .foregroundStyle(Theme.Covers.text.opacity(0.85))
                    .padding(isCompact ? Theme.Spacing.sm : Theme.Spacing.md)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }

            if showsText {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .textStyle(isCompact ? .subheading : .heading)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                    Text(subtitle)
                        .textStyle(isCompact ? .label : .caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(Theme.Covers.text)
                .shadow(color: Theme.Covers.shadow, radius: 2)
                .padding(.leading, spine + (isCompact ? 6 : 10))
                .padding(.trailing, isCompact ? 6 : 10)
                .padding(.bottom, isCompact ? Theme.Spacing.sm : Theme.Spacing.md)
            }

            Rectangle()
                .fill(Theme.Covers.spine)
                .frame(width: spine)
                .frame(maxHeight: .infinity)
        }
        .frame(width: size.width, height: size.height)
    }
}

// MARK: - Book

// One book on the shelf: a single button that opens its year or month. A
// grid cell with a cover, or at accessibility text sizes a list row with a
// small thumbnail.
struct JournalBook<Destination: View>: View {
    let title: String
    // "2026 journal", read out with the count.
    let spokenName: String
    let count: Int
    let accent: Color
    var coverImage: UIImage?
    var isCompact = false
    let hint: String
    @ViewBuilder let destination: () -> Destination

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            if dynamicTypeSize.isAccessibilitySize {
                row
            } else {
                BookCoverView(
                    title: title,
                    subtitle: JournalFormat.noteCount(count),
                    coverImage: coverImage,
                    accent: accent,
                    isCompact: isCompact
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(spokenName), \(JournalFormat.noteCount(count))")
        .accessibilityHint(hint)
    }

    private var row: some View {
        HStack(spacing: Theme.Spacing.lg) {
            BookCoverView(title: title, subtitle: "", coverImage: coverImage, accent: accent, isCompact: true, showsText: false)
                .frame(width: 64)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title)
                    .textStyle(.subheading)
                Text(JournalFormat.noteCount(count))
                    .textStyle(.callout)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .textStyle(.caption).fontWeight(.semibold)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
    }
}

// MARK: - Shelf

// A group of books: a header, then the books in an adaptive grid (two
// columns of years on a phone held upright, three of months, more in
// landscape) with at least 16 points between them. At accessibility text
// sizes the grid becomes a list of rows.
struct JournalShelf<Content: View>: View {
    let header: String
    // The narrowest a book may get, which sets how many columns fit.
    let minimumBookWidth: CGFloat
    @ViewBuilder let books: () -> Content

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var spacing: CGFloat = Theme.Spacing.lg

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            Text(header)
                .textStyle(.heading).fontWeight(.bold)
                .accessibilityAddTraits(.isHeader)

            if dynamicTypeSize.isAccessibilitySize {
                LazyVStack(spacing: spacing) { books() }
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: minimumBookWidth), spacing: spacing, alignment: .top)],
                    alignment: .leading,
                    spacing: spacing
                ) { books() }
            }
        }
    }
}

#Preview("Covers") {
    ScrollView {
        JournalShelf(header: "Years", minimumBookWidth: 150) {
            ForEach(0..<4, id: \.self) { index in
                BookCoverView(
                    title: String(2026 - index),
                    subtitle: "\(40 - index * 7) notes",
                    accent: Theme.Covers.accent(2026 - index)
                )
            }
        }
        .padding(Theme.Spacing.lg)
    }
}

#Preview("Dark") {
    ScrollView {
        JournalShelf(header: "Months", minimumBookWidth: 100) {
            ForEach(0..<6, id: \.self) { index in
                BookCoverView(
                    title: "October",
                    subtitle: "12 notes",
                    accent: Theme.Covers.accent(index),
                    isCompact: true
                )
            }
        }
        .padding(Theme.Spacing.lg)
    }
    .preferredColorScheme(.dark)
}
