import Foundation

// Every piece of text and every list on the About page lives here, so it can
// be edited in one place. AboutView and AcknowledgementsView only lay it out.
enum AppInfo {
    // MARK: App and developer

    static let appName = "Bloom"
    static let tagline = "A shared garden of memories"
    static let developerName = "Emily Du"
    static let studentID = "34942238"
    static let unit = "FIT3178 iOS App Development"
    static let university = "Monash University"

    // Read from the bundle, never hardcoded.
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    // "Version 1.0 (1)"
    static var versionLine: String { "Version \(version) (\(build))" }

    // MARK: About text

    static let aboutText = "Bloom is a journal for the small moments of your day, private unless you choose to share. Write notes with text, photos, voice memos and the movies or shows you've watched, share the ones you choose with friends, and watch your Greenhouse grow as your streaks do. Notes are saved on your device first and backed up to your account. Friends see the notes you share from today and your pinned notes."

    // Only features that exist in the app today.
    static let features: [Feature] = [
        Feature(title: "Notes with photos and voice memos", systemImage: "note.text"),
        Feature(title: "Movie and show reviews with a star rating", systemImage: "film"),
        Feature(title: "Drafts you can finish later", systemImage: "square.and.pencil"),
        Feature(title: "Journals by year, month and day", systemImage: "books.vertical"),
        Feature(title: "Friends, and private circles to choose who you see", systemImage: "person.2"),
        Feature(title: "Reactions, comments and replies", systemImage: "bubble.left.and.bubble.right"),
        Feature(title: "Daily reminders", systemImage: "bell"),
        Feature(title: "Light, dark or system appearance", systemImage: "circle.lefthalf.filled"),
        Feature(title: "A Greenhouse garden that grows with your streaks", systemImage: "leaf"),
    ]

    struct Feature: Identifiable {
        let title: String
        let systemImage: String
        var id: String { title }
    }

    // MARK: Footer

    static let footerCredit = "Made as part of FIT3178 at Monash University."
    static let tmdbAttribution = "This product uses the TMDB API but is not endorsed or certified by TMDB."
    static let thankYou = "Thank you to everyone who built the tools used in this app."

    // MARK: Acknowledgements

    struct Acknowledgement: Identifiable {
        let name: String
        let detail: String
        var license: String?
        var version: String?
        let url: URL
        var id: String { name }
    }

    private static func link(_ string: String) -> URL {
        // Every string below is a constant, so a bad one is a typo to fix here.
        URL(string: string) ?? URL(fileURLWithPath: "/")
    }

    private static let appleDocs = link("https://developer.apple.com/documentation")

    static let firebaseSDK = Acknowledgement(
        name: "Firebase iOS SDK",
        detail: "Authentication and Firestore, used for accounts, backup and sharing",
        license: "Apache License 2.0",
        version: "12.19.2",
        url: link("https://github.com/firebase/firebase-ios-sdk")
    )

    // Generated on 2026-10-30 from Package.resolved, with licenses read from
    // each package's LICENSE file in the SourcePackages checkouts. It does not
    // update itself, so refresh it after changing packages.
    static let firebasePackages: [Acknowledgement] = [
        Acknowledgement(name: "abseil-cpp-binary", detail: "Used by Firebase", license: "Apache License 2.0",
                        version: "1.2024072200.0", url: link("https://github.com/google/abseil-cpp-binary")),
        Acknowledgement(name: "app-check", detail: "Used by Firebase", license: "Apache License 2.0",
                        version: "11.3.2", url: link("https://github.com/google/app-check")),
        Acknowledgement(name: "google-ads-on-device-conversion-ios-sdk", detail: "Used by Firebase", license: "Apache License 2.0",
                        version: "3.7.0", url: link("https://github.com/googleads/google-ads-on-device-conversion-ios-sdk")),
        Acknowledgement(name: "GoogleAppMeasurement", detail: "Used by Firebase", license: "Apache License 2.0",
                        version: "12.19.2", url: link("https://github.com/google/GoogleAppMeasurement")),
        Acknowledgement(name: "GoogleDataTransport", detail: "Used by Firebase", license: "Apache License 2.0",
                        version: "10.1.1", url: link("https://github.com/google/GoogleDataTransport")),
        Acknowledgement(name: "GoogleUtilities", detail: "Used by Firebase", license: "Apache License 2.0",
                        version: "8.1.3", url: link("https://github.com/google/GoogleUtilities")),
        Acknowledgement(name: "grpc-binary", detail: "Used by Firebase", license: "Apache License 2.0",
                        version: "1.69.1", url: link("https://github.com/google/grpc-binary")),
        Acknowledgement(name: "gtm-session-fetcher", detail: "Used by Firebase", license: "Apache License 2.0",
                        version: "5.3.1", url: link("https://github.com/google/gtm-session-fetcher")),
        Acknowledgement(name: "interop-ios-for-google-sdks", detail: "Used by Firebase", license: "Apache License 2.0",
                        version: "101.0.0", url: link("https://github.com/google/interop-ios-for-google-sdks")),
        Acknowledgement(name: "leveldb", detail: "Used by Firebase", license: "BSD 3-Clause",
                        version: "1.22.5", url: link("https://github.com/firebase/leveldb")),
        Acknowledgement(name: "nanopb", detail: "Used by Firebase", license: "zlib",
                        version: "2.30910.1", url: link("https://github.com/firebase/nanopb")),
        Acknowledgement(name: "promises", detail: "Used by Firebase", license: "Apache License 2.0",
                        version: "2.4.1", url: link("https://github.com/google/promises")),
    ]

    static let services: [Acknowledgement] = [
        Acknowledgement(name: "The Movie Database (TMDB) API",
                        detail: "Movie and TV search and posters. \(tmdbAttribution)",
                        url: link("https://www.themoviedb.org")),
        Acknowledgement(name: "Firebase Authentication and Cloud Firestore",
                        detail: "Accounts, backup, friends and sharing",
                        url: link("https://firebase.google.com")),
    ]

    // Each framework is listed because the project imports it.
    static let appleFrameworks: [Acknowledgement] = [
        Acknowledgement(name: "SwiftUI", detail: "All of Bloom's screens", url: appleDocs),
        Acknowledgement(name: "SwiftData", detail: "Notes and movie logs saved on your device", url: appleDocs),
        Acknowledgement(name: "UserNotifications", detail: "Reminders and friend alerts", url: appleDocs),
        Acknowledgement(name: "PhotosUI", detail: "Choosing photos for notes and covers", url: appleDocs),
        Acknowledgement(name: "Contacts", detail: "Finding friends from your contacts", url: appleDocs),
        Acknowledgement(name: "AVFoundation", detail: "Recording and playing voice memos", url: appleDocs),
        Acknowledgement(name: "RealityKit", detail: "The 3D Greenhouse garden", url: appleDocs),
        Acknowledgement(name: "SF Symbols and Apple Color Emoji", detail: "Icons and emoji used across the app", url: appleDocs),
        Acknowledgement(name: "Human Interface Guidelines", detail: "The design guidance Bloom follows",
                        url: link("https://developer.apple.com/design/human-interface-guidelines")),
    ]

    static let designTools: [Acknowledgement] = [
        Acknowledgement(name: "Figma and Figma Make", detail: "Wireframes and early mockups",
                        url: link("https://www.figma.com")),
    ]

    static let learningSources: [Acknowledgement] = [
        Acknowledgement(name: "FIT3178 lab materials, Monash University",
                        detail: "Notifications and Firestore messaging labs",
                        url: link("https://www.monash.edu")),
        Acknowledgement(name: "Apple developer documentation", detail: "API reference and guides", url: appleDocs),
        Acknowledgement(name: "Firebase documentation", detail: "Authentication and Firestore guides",
                        url: link("https://firebase.google.com/docs")),
    ]

    static let generativeAINote = "Generative AI tools (Claude by Anthropic, and Figma Make) were used to help plan features, write and debug code, and generate early wireframes."
}
