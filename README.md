# Bloom 🌱

*A shared garden of memories*

Bloom is a journaling app for iOS, private unless you choose to share. Through the day you add short notes, with text and optionally a photo, a voice memo, or a movie or show you watched, and each one lands straight in today's timeline. There is no publish button. Notes stay on your device and in your own backup (stored with Google Firebase, not end to end encrypted) unless you choose to share them. Your Library of movies and shows is backed up the same way and is never shared. Friends only see the notes you share from today, plus any you pin to your profile, and the more you post, the better your plant grows in the Shared Garden.

Built for FIT3178 (iOS App Development) at Monash University by Emily Du (student ID 34942238).

## Status

The app is complete for the unit submission. Everything listed below is built and in the repository. Anything that isn't built is listed under [Known limitations](#known-limitations).

## Features

**Notes**
- Write a note with text, a photo (choose one or take one), a voice memo of up to 60 seconds, and an optional movie or show review
- Save a note as a draft, find it again in Drafts (also reachable from the new note sheet), then add it to today
- Edit, delete, pin (up to 3) or share any note from its three dot menu
- Today's Notes: swipe through today's notes as cards, each with its reactions, comments and quick add icons (camera, photo, microphone, movie or show)
- Home: today's notes as a timeline, with your friends' latest shared notes below

**Journals**
- Your Journals is a shelf of books, one per year. A year opens to its months, a month opens to a calendar that shades each day by how many notes you wrote, and a day opens as a timeline
- Give any year or month your own cover photo (covers are saved on the device only)

**Library**
- Search movies and TV shows (TMDB), rate them from 1 to 5 stars and add a review of up to 280 characters
- Attach an entry to a note, or log it on its own
- Entries are backed up privately to your account, with the TMDB poster link rather than the image, and come back when you sign in on a new install. Friends never see them
- Sort by date added, stars or title, and filter by movie or TV show, stars, and whether it has a review

**Friends and sharing**
- Find people by username (not case sensitive), a QR code or a link, then send, accept or decline requests
- Share your profile with a QR code or a `bloom://add/{uid}` link
- A friend's profile shows their pinned notes and a "View [name]'s notes" button, which opens only what they shared today
- Circles: named, private groups of up to 10 friends, with up to 10 circles. They choose who appears in the Greenhouse and on Home. They never decide who can read a note
- Share a note with friends from its menu, or turn on sharing for new notes in Settings. Friends can react, comment, and reply to comments

**Greenhouse**
- A 3D garden built with RealityKit. Each person gets one plant, and it blooms, wilts or dies depending on how long it has been since their last note (0 to 1 days blooming, 2 to 4 wilting, 5 or more dead)
- A preview sits in the Greenhouse tab, and tapping it opens a full screen version you can orbit and tap
- Switch between all friends and any circle, with a streak list underneath

**Notifications**
- A daily reminder at a time you choose, skipped on days that already have a note. Optionally it adapts to the time you usually write
- Friend alerts (new request, new shared note, comment or reply, reaction) appear as system notifications while Bloom is running, and always in the in-app notifications list

**Profile and settings**
- Profile picture, display name and username, with a pinned notes section
- Settings is split into Display (appearance and text size), Notifications, Privacy (sharing, permissions, backup) and About
- About lists the app details, the developer, acknowledgements and open source licences

**Accounts and data**
- Sign up and log in with a phone number (SMS) or an email and password
- Every account on a device gets its own local store, so one account never sees another's notes
- Notes are saved on the device first, so writing works offline, and are backed up to your account in Firestore (not end to end encrypted) so they come back after a reinstall

## How privacy works

- Notes, drafts and photos are saved locally in SwiftData first
- A backup of each note is kept at `users/{uid}/notes`. The intent is that only its owner can read it unless the note is marked shared, but that depends on the Firestore rules, which are set in the Firebase console
- A shared note can be read by your accepted friends, who can then comment, reply and react
- In the app, friends see only the notes you shared today and your pinned notes. The Firestore rules still allow an accepted friend to read any note you shared, so the "today only" limit is enforced by the app, not the database

## Tech stack

| Layer | Technology |
|---|---|
| UI | SwiftUI |
| Local persistence | SwiftData (one store per account) |
| Accounts | Firebase Authentication (phone and email) |
| Backup, sharing and friend data | Cloud Firestore |
| Garden | RealityKit |
| Photos and camera | PhotosUI, UIImagePickerController |
| Voice memos | AVFoundation |
| Notifications | UserNotifications |
| QR codes | Core Image |
| Movie and TV data | The Movie Database (TMDB) API |
| Tests | Swift Testing (unit), XCTest (UI) |

Dependencies are added with Swift Package Manager: the Firebase iOS SDK 12.19.2 (FirebaseAuth, FirebaseCore and FirebaseFirestore).

## Requirements

- Xcode 27 or later (the project was last upgraded in Xcode 27)
- iOS 26.5 or later. The test targets are set to iOS 27.0
- A free Firebase project (see below)
- A free TMDB API key, for movie and TV search

## Getting started

1. Clone this repository and open `Bloom.xcodeproj` in Xcode. Swift Package Manager downloads Firebase on first open.
2. Create a project at [console.firebase.google.com](https://console.firebase.google.com) and add an iOS app with the bundle identifier `Monash.Bloom` (or change it in the target and use your own).
3. Under Authentication, Sign-in method, enable **Phone** and **Email/Password**. Create a Firestore database.
4. Download `GoogleService-Info.plist` and add it to the Bloom target. **Do not commit this file.** It is listed in `.gitignore`.
5. In Firestore, publish security rules for the collections below. The rules are set in the Firebase console and are not stored in this repository.
6. Create the composite index on `notes` (`sharedWithFriends` ascending, `createdAt` descending). If it is missing, the Xcode console prints a link that creates it.
7. Get a free API key from [themoviedb.org](https://www.themoviedb.org) and put it in `Bloom/Info.plist` as the `TMDBAPIKey` string.
8. Choose an iPhone simulator and run. The camera and microphone usage descriptions are already set in the target's build settings, and the `bloom` URL scheme is registered in `Info.plist`.

Phone sign-up on a simulator needs reCAPTCHA or Firebase test numbers (Authentication, Sign-in method, Phone, Phone numbers for testing). Email sign-up works everywhere, so use it on simulators. To test friends, run two simulators signed in as different accounts. The simulator has no camera, so Take photo shows a message there.

## Firestore data

| Path | What it holds |
|---|---|
| `users/{uid}` | Username, display name, avatar flags and creation time |
| `users/{uid}/notes/{noteId}` | Backup of a note, with `isDraft`, `sharedWithFriends`, pin fields and photo or audio flags |
| `users/{uid}/notes/{noteId}/comments` | Comments and replies on a shared note |
| `users/{uid}/notes/{noteId}/reactions` | One reaction per person, with the document id as the reactor |
| `users/{uid}/photos/{noteId}` | A small compressed photo for a note |
| `users/{uid}/audio/{noteId}` | A small voice memo for a note |
| `users/{uid}/avatar/current` | A small profile picture |
| `users/{uid}/library/{entryId}` | A private backup of a Library entry: TMDB id, type, title, year, poster path (not the image), rating, review, logged date and the id of its note. Only its owner can read it |
| `users/{uid}/circles/{circleId}` | A private circle: its name and up to 10 member ids |
| `users/{uid}/activity/{id}` | Items in a person's notification list |
| `friendships/{from_to}` | A friend request and its status |
| `streaks/{uid}` | A person's current streak and last post date, read by friends for the garden |
| `sharedNotes/{id}` | Retired. The app no longer reads or writes it. Delete the collection in the Firebase console |

## Firestore rules

The rules are in `firestore.rules`, with `firebase.json` and `firestore.indexes.json` beside it. The emulator tests are in `rules-tests/`.

Run the rule tests (needs Node and Java; the first run downloads the Firestore emulator):

```
cd rules-tests
npm install
npm test
```

Deploy the rules and the index after the tests pass (log in once with `npx firebase login`, run from the repo root):

```
cd rules-tests
npx firebase deploy --only firestore:rules,firestore:indexes --config ../firebase.json --project bloom-726b7
```

What the rules enforce for friends: an accepted friend can read a shared note only if it is pinned or was created in the last 30 hours, and the same goes for its photo, voice memo, comments and reactions. The app narrows this to the viewer's calendar day, which a rule cannot know. Phone numbers are no longer stored in Firestore. One test is marked todo: any signed in user can still list `users`, because username search needs it.

## Running the tests

- Press **Cmd+U** to run everything
- **BloomTests** has 120 test functions in 12 Swift Testing suites, many of them parameterised. They cover streaks, reminder planning, plant growth states, phone numbers, usernames, journal grouping, movie and show reviews, TMDB parsing (with a stubbed network), comment threading, reactions, and journals, notes and pins in an in memory SwiftData store. They use a fixed UTC calendar, so they don't depend on the device's clock or time zone
- **BloomUITests** has 14 XCTest UI tests on the signed-out screens: Welcome, About, Sign Up, Log In and rotation. They find controls by accessibility identifier and attach screenshots to the test report
- Before running the UI tests, turn off Connect Hardware Keyboard in the Simulator (I/O, Keyboard), or typing fails
- Nothing in the automated tests signs in or uses the network. Sharing, friends and notifications were tested by hand with two simulators

## Project structure

```
Bloom/
├── Bloom/                       # The app
│   ├── App/                     # BloomApp, ContentView (the tab bar), PreviewContainer
│   ├── Core/                    # Used by two or more features
│   │   ├── Components/          # Shared views: avatars, note detail, timeline rows, reactions
│   │   ├── Firebase/            # Auth, friends, note backup, photo and audio stores, activity
│   │   ├── Models/              # Note, Journal, MediaLogEntry, circles, growth state
│   │   ├── Storage/             # Per account stores, account settings, image caches
│   │   ├── Streaks/             # Streak calculation and sync
│   │   ├── Theme/               # Colours, with light and dark values
│   │   └── Utilities/           # Validators, reminders, notification plumbing, TMDB client
│   └── Features/                # Used by one feature only
│       ├── Auth/  Home/  Notes/  Journals/  Library/
│       └── Friends/  Greenhouse/  Notifications/  Profile/  Settings/
├── BloomTests/                  # Unit tests
├── BloomUITests/                # UI tests
└── Bloom.xcodeproj
```

If only one feature uses a file, it goes in that feature. If two or more use it, it goes in `Core`.

## Known limitations

- **No push notifications.** Friend alerts are local notifications that Bloom posts while it is running, so nothing arrives when the app is closed. Real push needs a paid Apple Developer account, Firebase Cloud Messaging and Cloud Functions
- **Photos, voice memos and avatars are stored in Firestore**, as small compressed copies with size limits, not in Cloud Storage. Each sits behind a store protocol, so moving them later means changing one type
- **Journal covers stay on the device.** They are not backed up, and friends never see them
- **Library entries are backed up, but posters are not.** An entry is saved privately at `users/{uid}/library` with its TMDB poster path, and a restore downloads the poster from TMDB again. Entries logged before backup existed have no poster path, so after a restore they show without a poster
- **The "today only" view is enforced by the app.** The database rules would still let a modified app read older shared notes
- **Usernames are not unique**, which is why the share link uses the account id
- **A note is shared with all your friends, not with one circle.** Circles only choose who you see, not who can read a note
- **UI tests only cover the signed-out screens**, and the unit tests cover logic, not views or Firebase

## Possible next steps

- Push notifications through APNs, Firebase Cloud Messaging and Cloud Functions
- Cloud Storage for photos, voice memos and avatars
- Unique usernames, and database rules that enforce the today-only limit
- Showing a note to one circle only
- Reporting and blocking users, which the App Store requires for apps with user content

## Acknowledgements

Movie and TV data comes from The Movie Database (TMDB). This product uses the TMDB API but is not endorsed or certified by TMDB. Firebase is used for accounts and data. The full list of libraries, licences and sources is in the app under Settings, About, Acknowledgements.

Generative AI tools (Claude and Claude Code by Anthropic, and Figma Make) were used to help plan features, write and debug code, write tests and generate early wireframes.

## Author

Emily Du, Monash University, FIT3178
