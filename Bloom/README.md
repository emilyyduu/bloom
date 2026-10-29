# Bloom 🌱

*A shared garden of memories*

Bloom is a personal journaling app for iOS. Throughout the day you add short notes, text and, optionally, a photo, and they land straight in that day's timeline. No publish button, no waiting for a set time, a note just becomes part of your day the moment you write it. Notes stay private by default, but you can share one with a specific friend once they've accepted your request.

Built for FIT3178 (iOS App Development) at Monash University.

## Status

This is a student project, developed in weekly stages as part of a unit assignment. What's below reflects what's actually built as of **Week 8**, not the finished app. See [Roadmap](#roadmap) for what's still coming.

## Features (built so far)

- **Sign up and log in** with a phone number (SMS verification) or an email and password, via Firebase Authentication
- **Notes and drafts** — write a note with text and an optional photo, save it as a draft, or add it straight to today's journal
- **Daisy Chain** — a vertical timeline of the day's notes
- **Flipbook** — the same notes, swiped through one at a time
- **Your Journals** — every past day that has at least one note in it
- **Circles** — named, private groups of up to 10 friends, used to choose who appears in the Greenhouse garden and on Home. Circles never decide who can read a note
- **Friend search** — find someone by username, or match your phone contacts against registered accounts
- **Friend requests** — sending one shows as pending until the other person accepts
- **Sharing** — once a request is accepted, share a note with that friend

## Coming later

These are described in the project proposal but not built yet:

- Movie and TV logging via TMDB (Week 9)
- A local evening reminder, later made behaviour-driven based on journaling history (Weeks 9–10)
- **Shared Garden** — a 3D garden, built with SceneKit, where each friend's plant reflects their posting activity (Weeks 10–11, the project's Wow Factor)
- Photo sharing (currently sharing only copies a note's text)

## Tech stack

| Layer | Technology |
|---|---|
| UI | SwiftUI |
| Local persistence | SwiftData |
| Accounts | Firebase Authentication (Phone + Email/Password) |
| Sharing & friend data | Cloud Firestore |
| Friend discovery | Contacts framework |
| Photos | PhotosUI |
| Planned | SceneKit, AVFoundation, TMDB API, UserNotifications |

## Requirements

- Xcode 15 or later
- iOS 17.0+ (SwiftData isn't available on earlier versions)
- A free Firebase project (see setup below)

## Getting started

1. Clone this repo and open it in Xcode, or create a new iOS App project (SwiftUI, **Use SwiftData** checked, deployment target 17.0+) and drag in the `Bloom/` source folder.
2. Create a project at [console.firebase.google.com](https://console.firebase.google.com) and add an iOS app using this project's bundle identifier.
3. In the Firebase console, enable **Phone** and **Email/Password** under Authentication → Sign-in method, and create a Firestore database.
4. Download `GoogleService-Info.plist` and add it to the Xcode project. **Do not commit this file**, it's already in `.gitignore`.
5. Add the [Firebase iOS SDK](https://github.com/firebase/firebase-ios-sdk) via Swift Package Manager, including the `FirebaseAuth` and `FirebaseFirestore` products.
6. Add `NSContactsUsageDescription` to Info.plist (needed for phone-based friend search).
7. Build and run. Note creation, drafts, Daisy Chain, and Flipbook all work fully offline; sign-up, friend search, and sharing need the Firebase project above and an internet connection.

Full setup notes, including phone auth's push/reCAPTCHA requirement and suggested Firestore security rules, are in [`Bloom/README.md`](Bloom/README.md).

## Project structure

```
Bloom/
├── BloomApp.swift          # App entry point, Firebase setup, auth-gated root view
├── Models/                 # SwiftData models (Note, Journal) + Firestore user record
├── Views/                  # SwiftUI views: auth flow, journaling, friends & sharing
└── Services/                # AuthService, FriendService, SharingService
```

## Roadmap

| Week | Focus |
|---|---|
| 6 | Sign-up/login (Firebase Auth) + the SwiftData model |
| 7 | Note creation, daily journal grouping, Daisy Chain, Flipbook |
| 8 | Friend search (username + contacts), friend requests, sharing |
| 9 | Media logging (TMDB) + basic local reminder |
| 10 | Behaviour-driven notifications extension + start of the Wow Factor |
| 11 | Shared Garden (SceneKit) |
| 12 | Testing, polish, submission |

## Author

Emily Du — Monash University, FIT3178
