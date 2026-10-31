import SwiftUI
import SwiftData

// MARK: - Sort and filter options

enum LibrarySort: String, CaseIterable, Identifiable {
    case newestAdded, oldestAdded, highestRated, lowestRated, titleAToZ

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newestAdded: return "Newest added"
        case .oldestAdded: return "Oldest added"
        case .highestRated: return "Highest rated"
        case .lowestRated: return "Lowest rated"
        case .titleAToZ: return "Title A to Z"
        }
    }
}

enum LibraryTypeFilter: String, CaseIterable, Identifiable {
    case all, movies, tvShows

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .movies: return "Movies"
        case .tvShows: return "TV shows"
        }
    }
}

enum LibraryStarsFilter: String, CaseIterable, Identifiable {
    case any, fiveStars, fourAndUp, threeAndUp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: return "Any"
        case .fiveStars: return "5 stars"
        case .fourAndUp: return "4 stars and up"
        case .threeAndUp: return "3 stars and up"
        }
    }

    var minimumRating: Int {
        switch self {
        case .any: return 1
        case .fiveStars: return 5
        case .fourAndUp: return 4
        case .threeAndUp: return 3
        }
    }
}

enum LibraryReviewFilter: String, CaseIterable, Identifiable {
    case any, hasReview

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: return "Any"
        case .hasReview: return "Has a review"
        }
    }
}

// The Library's sort and filter choices. Kept per account in
// AccountDefaults. Applying them only reorders and filters entries
// already loaded, nothing is queried or written to the store.
struct LibraryOptions: Equatable {
    var sort = LibrarySort.newestAdded
    var type = LibraryTypeFilter.all
    var stars = LibraryStarsFilter.any
    var review = LibraryReviewFilter.any

    enum FilterKind: Hashable {
        case type, stars, review
    }

    struct Chip: Identifiable {
        let kind: FilterKind
        let title: String
        var id: FilterKind { kind }
    }

    var chips: [Chip] {
        var result: [Chip] = []
        if type != .all { result.append(Chip(kind: .type, title: type.title)) }
        if stars != .any { result.append(Chip(kind: .stars, title: stars.title)) }
        if review != .any { result.append(Chip(kind: .review, title: review.title)) }
        return result
    }

    var hasActiveFilters: Bool { !chips.isEmpty }

    // Spoken after "Filters:" in accessibility labels.
    var filterDescription: String {
        hasActiveFilters ? chips.map(\.title).joined(separator: ", ") : "none"
    }

    mutating func remove(_ kind: FilterKind) {
        switch kind {
        case .type: type = .all
        case .stars: stars = .any
        case .review: review = .any
        }
    }

    mutating func clearFilters() {
        type = .all
        stars = .any
        review = .any
    }

    func apply(to entries: [MediaLogEntry]) -> [MediaLogEntry] {
        let filtered = entries.filter { entry in
            switch type {
            case .all: break
            case .movies: if entry.mediaType != "movie" { return false }
            case .tvShows: if entry.mediaType != "tv" { return false }
            }
            if entry.rating < stars.minimumRating { return false }
            if review == .hasReview {
                let text = entry.reviewText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if text.isEmpty { return false }
            }
            return true
        }

        // Every order breaks ties by date added, newest first.
        return filtered.sorted { a, b in
            switch sort {
            case .newestAdded:
                break
            case .oldestAdded:
                if a.loggedAt != b.loggedAt { return a.loggedAt < b.loggedAt }
            case .highestRated:
                if a.rating != b.rating { return a.rating > b.rating }
            case .lowestRated:
                if a.rating != b.rating { return a.rating < b.rating }
            case .titleAToZ:
                let order = a.title.localizedStandardCompare(b.title)
                if order != .orderedSame { return order == .orderedAscending }
            }
            return a.loggedAt > b.loggedAt
        }
    }
}

// The Sort and Filter menus, shown in the Journal header while the
// Library segment is selected. A checkmark marks the chosen item in
// each group.
struct LibraryOptionsMenus: View {
    @Binding var options: LibraryOptions

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Menu {
                Picker("Sort", selection: $options.sort) {
                    ForEach(LibrarySort.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Sort")
            .accessibilityValue(options.sort.title)

            Menu {
                Section("Type") {
                    Picker("Type", selection: $options.type) {
                        ForEach(LibraryTypeFilter.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("Stars") {
                    Picker("Stars", selection: $options.stars) {
                        ForEach(LibraryStarsFilter.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("Review") {
                    Picker("Review", selection: $options.review) {
                        ForEach(LibraryReviewFilter.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            } label: {
                Image(systemName: options.hasActiveFilters
                    ? "line.3.horizontal.decrease.circle.fill"
                    : "line.3.horizontal.decrease.circle")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Filter")
            .accessibilityValue(options.hasActiveFilters ? "Active: \(options.filterDescription)" : "No filters")
        }
    }
}

// MARK: - Library

// The Library segment of the Journal tab: a showcase grid of every
// movie and show the user has logged.
struct LibraryView: View {
    @Binding var options: LibraryOptions
    // Opens the same search as the magnifying glass in the header.
    var onAddMedia: () -> Void = {}

    @Query(sort: \MediaLogEntry.loggedAt, order: .reverse) private var entries: [MediaLogEntry]
    @State private var selectedEntry: MediaLogEntry?
    @ScaledMetric(relativeTo: .body) private var minimumColumnWidth: CGFloat = 110
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    // Entries on a draft only appear once the note is posted.
    private var visibleEntries: [MediaLogEntry] {
        entries.filter { $0.note?.isDraft != true }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: minimumColumnWidth), spacing: Theme.Spacing.lg, alignment: .top)]
    }

    var body: some View {
        let visible = visibleEntries
        let shown = options.apply(to: visible)

        Group {
            if visible.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    if options.hasActiveFilters {
                        filterSummary(shownCount: shown.count, totalCount: visible.count)
                    }

                    if shown.isEmpty {
                        ContentUnavailableView {
                            Label("Nothing matches these filters", systemImage: "line.3.horizontal.decrease.circle")
                        } actions: {
                            Button("Clear filters") { options.clearFilters() }
                                .buttonStyle(.bloomSecondary)
                        }
                    } else {
                        grid(of: shown)
                    }
                }
            }
        }
        .sheet(item: $selectedEntry) { entry in
            MediaLogEntryDetailView(entry: entry)
        }
    }

    // Same layout as the empty state in Today's Notes: icon, title,
    // subheading and a full width primary button.
    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.lg) {
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "film")
                    .textStyle(.display)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityHidden(true)
                Text("Nothing logged yet")
                    .textStyle(.heading)
                Text("Movies and shows you log will show up here.")
                    .textStyle(.callout)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)

            Button("Log a movie or show", action: onAddMedia)
                .buttonStyle(.bloomPrimary)
        }
        .padding(.horizontal, Theme.Spacing.screenEdge)
        .frame(maxWidth: 400)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func grid(of shown: [MediaLogEntry]) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: Theme.Spacing.xl) {
                AddMediaTile(action: onAddMedia)

                ForEach(shown) { entry in
                    Button {
                        selectedEntry = entry
                    } label: {
                        MediaLogEntryCell(entry: entry)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(cellLabel(for: entry))
                    .accessibilityHint("Opens details")
                }
            }
            .padding(Theme.Spacing.lg)
        }
    }

    // MARK: Active filters

    // Each active filter as a chip with an x, then the result count and
    // Clear all. At accessibility sizes the chips stack so none is cut
    // off, otherwise they scroll sideways, which also suits landscape.
    private func filterSummary(shownCount: Int, totalCount: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 0) {
                    chipButtons
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.sm) {
                        chipButtons
                    }
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack {
                    countText(shownCount: shownCount, totalCount: totalCount)
                    Spacer(minLength: Theme.Spacing.sm)
                    clearAllButton
                }
                VStack(alignment: .leading, spacing: 0) {
                    countText(shownCount: shownCount, totalCount: totalCount)
                    clearAllButton
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.sm)
    }

    private var chipButtons: some View {
        ForEach(options.chips) { chip in
            Button {
                options.remove(chip.kind)
            } label: {
                HStack(spacing: 6) {
                    Text(chip.title)
                    Image(systemName: "xmark")
                        .textStyle(.caption).fontWeight(.bold)
                        .accessibilityHidden(true)
                }
                .textStyle(.callout)
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, 6)
                .background(Capsule().fill(Theme.Colors.surfaceMuted))
                .overlay(Capsule().strokeBorder(Theme.Colors.separator, lineWidth: 1))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(chip.title), filter on")
            .accessibilityHint("Removes this filter")
        }
    }

    private func countText(shownCount: Int, totalCount: Int) -> some View {
        Text("\(shownCount) of \(totalCount)")
            .textStyle(.callout)
            .foregroundStyle(Theme.Colors.textSecondary)
            .accessibilityLabel(
                "Showing \(shownCount) of \(totalCount). Sorted by \(options.sort.title). Filters: \(options.filterDescription)"
            )
    }

    private var clearAllButton: some View {
        Button("Clear all") { options.clearFilters() }
            .textStyle(.callout)
            .frame(minHeight: 44)
    }
}

// A blank poster sized slot with a plus, always first in the grid, so
// adding a movie or show is one tap away.
private struct AddMediaTile: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .textStyle(.heading)
                .foregroundStyle(Theme.Colors.greenText)
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                        .fill(Theme.Colors.surfaceMuted)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                        .strokeBorder(Theme.Colors.separator, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Log a movie or show")
        .accessibilityHint("Searches for a movie or show to add")
    }
}

private func cellLabel(for entry: MediaLogEntry) -> String {
    var text = "\(entry.title), \(entry.rating) out of 5 stars"
    if let line = entry.reviewFirstLine { text += ". \(line)" }
    return text
}

private struct MediaLogEntryCell: View {
    let entry: MediaLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            posterImage
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))

            Text(entry.title)
                .textStyle(.callout)
                .fontWeight(.medium)
                .lineLimit(2)
                .foregroundStyle(Theme.Colors.textPrimary)

            StarRatingView(rating: entry.rating)

            if let line = entry.reviewFirstLine {
                Text(line)
                    .textStyle(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private var posterImage: some View {
        if let image = entry.posterImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Rectangle()
                .fill(Theme.Colors.surfaceMuted)
                .overlay {
                    Image(systemName: "film")
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
        }
    }
}

#Preview {
    LibraryView(options: .constant(LibraryOptions()))
        .modelContainer(PreviewContainer.shared)
}

// An in memory store with a few entries, so the filtered previews have
// something to show.
@MainActor
private func previewContainerWithEntries() -> ModelContainer {
    let container = try! ModelContainer(
        for: MediaLogEntry.self, Note.self, Journal.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let samples: [(String, String, Int, String?)] = [
        ("Paddington", "movie", 5, "Warm and funny."),
        ("The Bear", "tv", 5, nil),
        ("Past Lives", "movie", 4, "Quiet and devastating."),
        ("Cats", "movie", 1, nil),
    ]
    for (index, sample) in samples.enumerated() {
        let entry = MediaLogEntry(tmdbID: -index - 1, title: sample.0, mediaType: sample.1, releaseYear: nil, posterFileName: nil, rating: sample.2)
        entry.reviewText = sample.3
        container.mainContext.insert(entry)
    }
    return container
}

#Preview("Filtered") {
    LibraryView(options: .constant(LibraryOptions(type: .movies, stars: .fourAndUp, review: .hasReview)))
        .modelContainer(previewContainerWithEntries())
}

#Preview("Filtered - Accessibility 5") {
    LibraryView(options: .constant(LibraryOptions(type: .movies, stars: .fourAndUp, review: .hasReview)))
        .modelContainer(previewContainerWithEntries())
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("No matches") {
    LibraryView(options: .constant(LibraryOptions(type: .tvShows, stars: .fiveStars, review: .hasReview)))
        .modelContainer(previewContainerWithEntries())
}
