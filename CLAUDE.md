Bloom

iOS journaling app for FIT3178. SwiftUI, SwiftData, iOS 17+.

## Rules that matter
- There is NO publish time and no publish button. A note appears in
  today's Daisy Chain as soon as it is saved. A Journal is just the
  notes grouped by date.
- Accounts use Firebase Auth (phone via SMS, or email and password).
  Friends are found by username or by matching phone contacts, and a
  friend request must be accepted before anything can be shared.
- SwiftData holds all private notes locally. Firestore is only for
  user records, friendships and shared notes.
- Use standard SwiftUI components and SF Symbols. Follow Apple's HIG.
- No em dashes in any user-facing text.

## Current stage
Weeks 6 to 8 are built (auth, notes, Daisy Chain, Flipbook, friend
search, sharing). Not built yet: TMDB media logging, notifications,
the SceneKit Shared Circle Garden.

## Setup
Needs GoogleService-Info.plist (never commit it) and the Firebase
packages FirebaseCore, FirebaseAuth, FirebaseFirestore.
