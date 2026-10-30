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
            return "TMDB is not configured. Add a TMDBAPIKey value to the app's Info.plist."
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
// logged entries. The API key is never hardcoded, it's read from the
// TMDBAPIKey entry in Info.plist so it can be added outside source
// control.
final class TMDBService {
    static let shared = TMDBService()
    private init() {}

    private let baseURL = URL(string: "https://api.themoviedb.org/3")!

    private var apiKey: String? {
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
            (data, response) = try await URLSession.shared.data(from: url)
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
            (data, response) = try await URLSession.shared.data(from: url)
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
