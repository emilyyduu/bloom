import SwiftUI

// The read-only row of filled and empty stars used to show a saved
// rating in the Library grid, entry detail view and note chips.
struct StarRatingView: View {
    let rating: Int
    var font: Font = .footnote

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
            }
        }
        .font(font)
        .foregroundStyle(Theme.Palette.mustard)
        .accessibilityElement()
        .accessibilityLabel("\(rating) out of 5 stars")
    }
}

// The interactive star picker used when logging a new entry or editing
// an existing one's rating.
struct StarRatingPicker: View {
    @Binding var rating: Int

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    rating = star
                } label: {
                    Image(systemName: star <= rating ? "star.fill" : "star")
                        .textStyle(.heading)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
                .accessibilityAddTraits(star == rating ? .isSelected : [])
            }
        }
        .foregroundStyle(Theme.Palette.mustard)
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.xl) {
        StarRatingView(rating: 3)
        StarRatingPicker(rating: .constant(4))
    }
}
