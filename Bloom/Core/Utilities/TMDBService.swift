import Foundation

// A single movie or TV result from a TMDB search, trimmed down to what
// the Library needs to show a result and, if logged, save an entry.
struct SearchResult: Identifiable {
    let id: Int
    let title: String
    let mediaType: String // "movie" or "tv"
    let releaseYear: Int?
    let posterPath: String?
}

enum TMDBServiceError: LocalizedError {
    case missingAPIKey
    case noConnection
    case emptyResults
    case badResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Movie search is not available in this build."
        case .noConnection:
            return "Check your connection and try again."
        case .emptyResults:
            return "No movies or shows matched your search."
        case .badResponse:
            return "TMDB could not be reached right now. Try again later."
        }
    }
}

// Talks to TMDB's /search/multi endpoint and downloads posters for
// logged entries. The API key is not in the source or in Info.plist's
// text: Info.plist's TMDBAPIKey is filled in at build time from
// TMDB_API_KEY in the gitignored Config/Secrets.xcconfig. It is still
// inside the shipped app, so treat it as readable by anyone who has it.
final class TMDBService {
    static let shared = TMDBService()

    private let session: URLSession
    private let apiKeyOverride: String?

    // `session` and `apiKey` exist so tests can use a stub session and a
    // fixed key. The app only ever uses `shared`.
    init(session: URLSession = .shared, apiKey: String? = nil) {
        self.session = session
        self.apiKeyOverride = apiKey
    }

    private let baseURL = URL(string: "https://api.themoviedb.org/3")!

    private var apiKey: String? {
        if let apiKeyOverride { return apiKeyOverride }
        guard
            let key = Bundle.main.object(forInfoDictionaryKey: "TMDBAPIKey") as? String,
            !key.isEmpty
        else {
            return nil
        }
        return key
    }

    func search(query: String) async throws -> [SearchResult] {
        guard let apiKey else { throw TMDBServiceError.missingAPIKey }
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        var components = URLComponents(
            url: baseURL.appendingPathComponent("search/multi"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "include_adult", value: "false"),
        ]
        guard let url = components?.url else { throw TMDBServiceError.badResponse }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw TMDBServiceError.noConnection
        }

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw TMDBServiceError.badResponse
        }

        guard let decoded = try? JSONDecoder().decode(TMDBSearchResponse.self, from: data) else {
            throw TMDBServiceError.badResponse
        }

        let results = decoded.results.compactMap(\.asSearchResult)
        guard !results.isEmpty else { throw TMDBServiceError.emptyResults }
        return results
    }

    func posterURL(path: String, size: String = "w342") -> URL? {
        URL(string: "https://image.tmdb.org/t/p/\(size)\(path)")
    }

    // Downloads a poster once into Documents/Posters and returns the
    // saved file name, so Library can load posters from disk and work
    // offline afterwards.
    func downloadPoster(path: String) async throws -> String {
        guard let url = posterURL(path: path) else { throw TMDBServiceError.badResponse }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw TMDBServiceError.noConnection
        }

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw TMDBServiceError.badResponse
        }

        let postersDirectory = FileManager.documentsDirectory
            .appendingPathComponent(MediaLogEntry.postersDirectoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: postersDirectory, withIntermediateDirectories: true)

        let fileName = "\(UUID().uuidString).jpg"
        try data.write(to: postersDirectory.appendingPathComponent(fileName))
        return fileName
    }
}

private struct TMDBSearchResponse: Decodable {
    let results: [TMDBSearchResultItem]
}

private struct TMDBSearchResultItem: Decodable {
    let id: Int
    let mediaType: String?
    let title: String?
    let name: String?
    let releaseDate: String?
    let firstAirDate: String?
    let posterPath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case mediaType = "media_type"
        case title
        case name
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case posterPath = "poster_path"
    }

    var asSearchResult: SearchResult? {
        guard let mediaType, mediaType == "movie" || mediaType == "tv" else { return nil }
        guard let resolvedTitle = mediaType == "movie" ? title : name else { return nil }

        let dateString = mediaType == "movie" ? releaseDate : firstAirDate
        let releaseYear = dateString.flatMap { $0.count >= 4 ? Int($0.prefix(4)) : nil }

        return SearchResult(
            id: id,
            title: resolvedTitle,
            mediaType: mediaType,
            releaseYear: releaseYear,
            posterPath: posterPath
        )
    }
}
