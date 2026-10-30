import Foundation
import Testing
@testable import Bloom

// Answers every request from a closure, so no test touches the network.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (URLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// One suite and serialised, because the stub's handler is shared state.
@MainActor
@Suite("TMDB search", .serialized)
struct TMDBServiceTests {
    // A /search/multi answer with two movies, a TV show, a person, an
    // unknown type, and entries missing the field their type needs.
    static let sample = """
    {
      "page": 1,
      "results": [
        {"id": 603, "media_type": "movie", "title": "The Matrix", "release_date": "1999-03-30", "poster_path": "/matrix.jpg"},
        {"id": 1396, "media_type": "tv", "name": "Breaking Bad", "first_air_date": "2008-01-20", "poster_path": "/bb.jpg"},
        {"id": 6384, "media_type": "person", "name": "Keanu Reeves", "profile_path": "/keanu.jpg"},
        {"id": 7, "media_type": "movie", "title": "No Date Movie", "release_date": "", "poster_path": null},
        {"id": 8, "media_type": "tv", "name": "Short Date Show", "first_air_date": "20"},
        {"id": 9, "media_type": "tv", "title": "Wrong Field For TV"},
        {"id": 10, "media_type": "collection", "name": "A Collection"},
        {"id": 11, "title": "No Media Type"}
      ],
      "total_results": 8
    }
    """

    private func service(
        status: Int = 200,
        body: String = sample,
        record: ((URLRequest) -> Void)? = nil
    ) -> TMDBService {
        StubURLProtocol.handler = { request in
            record?(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (response, Data(body.utf8))
        }
        return makeService()
    }

    private func makeService() -> TMDBService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return TMDBService(session: URLSession(configuration: configuration), apiKey: "test-key")
    }

    private func expectError(_ expected: TMDBServiceError, from service: TMDBService, query: String = "matrix") async {
        do {
            _ = try await service.search(query: query)
            Issue.record("Expected \(expected) but the search succeeded")
        } catch let error as TMDBServiceError {
            #expect(error == expected)
        } catch {
            Issue.record("Expected \(expected) but got \(error)")
        }
    }

    @Test("Movies and TV are kept and people and other types are dropped")
    func keepsMoviesAndTV() async throws {
        let results = try await service().search(query: "matrix")
        #expect(results.map(\.id) == [603, 1396, 7, 8])
        #expect(results.map(\.mediaType) == ["movie", "tv", "movie", "tv"])
    }

    @Test("A movie takes its title and release year, a show its name and first air year")
    func titlesAndYears() async throws {
        let results = try await service().search(query: "matrix")
        let movie = try #require(results.first { $0.id == 603 })
        let show = try #require(results.first { $0.id == 1396 })
        #expect(movie.title == "The Matrix")
        #expect(movie.releaseYear == 1999)
        #expect(movie.posterPath == "/matrix.jpg")
        #expect(show.title == "Breaking Bad")
        #expect(show.releaseYear == 2008)
    }

    @Test("A missing, empty or too short date gives no year, and a missing poster stays nil")
    func missingFields() async throws {
        let results = try await service().search(query: "matrix")
        let noDate = try #require(results.first { $0.id == 7 })
        let shortDate = try #require(results.first { $0.id == 8 })
        #expect(noDate.releaseYear == nil)
        #expect(noDate.posterPath == nil)
        #expect(shortDate.releaseYear == nil)
    }

    @Test("The request goes to /search/multi with the key, the query and adult results off")
    func requestShape() async throws {
        nonisolated(unsafe) var captured: URL?
        _ = try await service(record: { captured = $0.url }).search(query: "the matrix")

        let url = try #require(captured)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        #expect(url.host == "api.themoviedb.org")
        #expect(url.path == "/3/search/multi")
        #expect(value("query") == "the matrix")
        #expect(value("api_key") == "test-key")
        #expect(value("include_adult") == "false")
    }

    @Test("A blank query returns nothing without making a request", arguments: ["", "   ", "\n"])
    func blankQuery(query: String) async throws {
        nonisolated(unsafe) var requests = 0
        let results = try await service(record: { _ in requests += 1 }).search(query: query)
        #expect(results.isEmpty)
        #expect(requests == 0)
    }

    @Test("Results that are all people give the no results error")
    func onlyPeople() async {
        let body = #"{"results":[{"id":1,"media_type":"person","name":"Someone"}]}"#
        await expectError(.emptyResults, from: service(body: body))
    }

    @Test("An empty results list gives the no results error")
    func emptyList() async {
        await expectError(.emptyResults, from: service(body: #"{"results":[]}"#))
    }

    @Test("A non 200 status gives the bad response error", arguments: [401, 404, 429, 500, 503])
    func badStatus(status: Int) async {
        await expectError(.badResponse, from: service(status: status))
    }

    @Test("A body that isn't the expected JSON gives the bad response error", arguments: [
        "not json at all", "", "{}", #"{"results":"oops"}"#, #"{"results":[{"media_type":"movie"}]}"#,
    ])
    func badBody(body: String) async {
        await expectError(.badResponse, from: service(body: body))
    }

    @Test("A response that isn't HTTP gives the bad response error")
    func notHTTP() async {
        StubURLProtocol.handler = { request in
            (URLResponse(url: request.url!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil), Data())
        }
        await expectError(.badResponse, from: makeService())
    }

    @Test("A failed connection gives the no connection error")
    func offline() async {
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        await expectError(.noConnection, from: makeService())
    }

    @Test("Every error has a message with no em dash")
    func errorMessages() {
        let all: [TMDBServiceError] = [.missingAPIKey, .noConnection, .emptyResults, .badResponse]
        for error in all {
            let message = error.errorDescription ?? ""
            #expect(!message.isEmpty)
            #expect(!message.contains("\u{2014}"))
        }
    }

    @Test("Poster URLs use the image host, the size and the path")
    func posterURL() {
        let service = makeService()
        #expect(service.posterURL(path: "/abc.jpg")?.absoluteString == "https://image.tmdb.org/t/p/w342/abc.jpg")
        #expect(service.posterURL(path: "/abc.jpg", size: "w92")?.absoluteString == "https://image.tmdb.org/t/p/w92/abc.jpg")
    }
}
