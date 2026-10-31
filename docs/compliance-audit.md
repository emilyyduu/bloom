# Bloom compliance audit

Audited on 2026-10-31 against branch `dev` (commit 92ed0f8). Read only: no app file was changed.
Developer: Emily Du, Victoria, Australia (eduu0005@student.monash.edu). Assumed worldwide App Store distribution, minimum age 16.

This is an engineering review, not legal advice. Nothing here says Bloom is "compliant". Items marked LAWYER need a qualified person.

Evidence labels: **VERIFIED IN CODE** (file cited), **APPLE GUIDELINES** (guideline number), **LAW** (name the law, verify with the official source), **UNSURE**.

Limits of this audit:
- The Firestore security rules are not in the repository (README: "set in the Firebase console"). Every statement about what the server allows is UNSURE until you export and read the rules.
- I did not run the app, check Firebase console settings, or inspect the built binary's linked frameworks.
- I did not browse the web. TMDB, Firebase and Apple terms below are from memory and must be re-read at the official pages.

---

## 1. What data Bloom collects

| Data | Where it is stored | Why | Evidence |
|---|---|---|---|
| Email and password | Firebase Authentication (Google). Email is never written to Firestore | Sign in | VERIFIED: `AuthService.swift` (`createUser`, `createUserProfile` comment "email is never written") |
| Phone number (phone sign up) | Firebase Auth, plus `users/{uid}.phoneNumber` in Firestore (normalised) | Sign in by SMS; friend discovery by contacts | VERIFIED: `AuthService.createUserProfile`, `PhoneVerificationView.verify` |
| Display name, username, usernameLower, createdAt | `users/{uid}` | Shown to friends, search | VERIFIED: `AuthService.createUserProfile` |
| Profile picture (256x256 JPEG, under 100 KB) | `users/{uid}/avatar/current`, flags on `users/{uid}` | Profile | VERIFIED: `AvatarStore.swift` |
| Notes (text, dates, draft/shared/pinned flags) | SwiftData on device, backup to `users/{uid}/notes` | Journal; backup; sharing | VERIFIED: `NoteSyncService.swift`, README |
| Note photos (small JPEG) | Device; backup at `users/{uid}/photos/{noteId}` | Backup, friends view | VERIFIED: `PhotoStore.swift` |
| Voice memos (up to 60 s, AAC) | Device (`Documents/audio`); backup at `users/{uid}/audio/{noteId}`; friends download on play | Backup, sharing | VERIFIED: `AudioStore.swift`, `VoiceMemoRecorder.swift` |
| Movie and show log (rating, review up to 280 chars, poster) | Device only, never backed up | Library | VERIFIED: CLAUDE.md, `TMDBService.downloadPoster` |
| Journal cover photos | Device only | Cosmetic | VERIFIED: `JournalCoverStore.swift` |
| Friend relationships | `friendships/{from_to}` (fromUID, toUID, status) | Friends | VERIFIED: `FriendService.swift` |
| Circles (name, up to 10 member UIDs) | `users/{uid}/circles` | Private grouping | VERIFIED: `CircleStore.swift` |
| Streak (currentStreak, lastPostDate, updatedAt) | `streaks/{uid}`, read by friends | Garden | VERIFIED: `StreakSyncService.swift` line 33 |
| Comments, replies, reactions | `users/{owner}/notes/{id}/comments` and `/reactions` | Social | VERIFIED: `CommentService.swift`, `ReactionService.swift` |
| Notification feed items (type, fromUID, preview up to 120 chars) | `users/{recipient}/activity` | In-app feed and local alerts | VERIFIED: `ActivityStore.swift` |
| Phone contacts | Read on device only when the user taps contact search. Normalised numbers are sent to Firestore as query values (`in` queries, 30 at a time). Not stored by the app | Find friends | VERIFIED: `FriendService.searchByContacts` lines 96-133 |
| Preferences (reminder time, toggles, appearance, selected circle) | UserDefaults on device | Settings | VERIFIED: `AccountDefaults.swift` |
| Legacy shared notes | `sharedNotes` collection | Old sharing design, code still present | VERIFIED: `SharingService.swift`; README says superseded |
| TMDB search text | Sent to `api.themoviedb.org` with the app's API key; posters from `image.tmdb.org` | Library search | VERIFIED: `TMDBService.swift` |
| Push token | Not used. No remote push registered | n/a | VERIFIED: grep for `registerForRemoteNotifications` found nothing |

Stays on device only: movie log, cover photos, drafts until first backup, settings, caches of friend photos and avatars.
Goes to Firebase: everything else in the table.

Not collected: no location, no analytics events, no advertising ID.

---

## 2. Tracking and third parties

**Swift packages (Package.resolved):** firebase-ios-sdk 12.19.2, GoogleAppMeasurement 12.19.2, google-ads-on-device-conversion-ios-sdk 3.7.0, app-check 11.3.2, GoogleDataTransport 10.1.1, GoogleUtilities 8.1.3, grpc-binary 1.69.1, gtm-session-fetcher 5.3.1, interop-ios-for-google-sdks 101.0.0, leveldb 1.22.5, nanopb 2.30910.1, promises 2.4.1, abseil-cpp-binary 1.2024072200.0.

The target links only FirebaseAuth, FirebaseCore and FirebaseFirestore (VERIFIED: `project.pbxproj`). GoogleAppMeasurement and the Google Ads on-device conversion package are resolved because they belong to the Firebase package, not because Bloom links them. UNSURE: confirm in the built app (Frameworks folder / Xcode link phase) that FirebaseAnalytics and GoogleAppMeasurement are not embedded.

**Hosts contacted:** Firebase Auth, Firestore and (for phone sign in) Google reCAPTCHA / SMS endpoints (`*.googleapis.com`, `firestore.googleapis.com`, `identitytoolkit.googleapis.com`, `securetoken.googleapis.com`); `api.themoviedb.org`; `image.tmdb.org`. APPLE: the bloom:// URL scheme is local only.

**Analytics, ads, tracking:** none in code. VERIFIED: no `ASIdentifierManager`, `AppTrackingTransparency`, `advertisingIdentifier`, `Analytics` or `logEvent` anywhere in Swift sources. `GoogleService-Info.plist` has `IS_ADS_ENABLED` false and `IS_ANALYTICS_ENABLED` false (VERIFIED).

**App Tracking Transparency:** not needed as the app stands (APPLE GUIDELINES 5.1.2(i): ATT is for tracking across other companies' apps/sites). No `NSUserTrackingUsageDescription` is present, which is correct. Re-check if you ever add Analytics, ads or a third party that links your users to other data.

### TMDB terms: where Bloom falls short
From memory, to be re-read at themoviedb.org/api-terms-of-use and the logo/attribution page:

| Requirement (verify) | Bloom today | Gap |
|---|---|---|
| Attribution wording "This product uses the TMDB API but is not endorsed or certified by TMDB." | `AppInfo.tmdbAttribution`, shown in About footer | OK (VERIFIED). |
| Show the TMDB logo with the attribution, logo less prominent than your own | `AboutView` shows the logo only if `UIImage(named: "TMDBLogo")` exists. `TMDBLogo.svg` sits loose in `Assets.xcassets`, not inside an `.imageset`, so the lookup very probably returns nil and the logo never shows (VERIFIED file layout; behaviour UNSURE, check on device) | Must fix. |
| Commercial use needs a separate agreement; free API is for non-commercial use | App is free, no ads or purchases | UNSURE. If you ever charge or monetise, contact TMDB. App Store publication by an individual of a free app may still be judged "commercial" by TMDB: ask them. |
| API key is yours, not to be shared | Key is a plain string in `Bloom/Info.plist` (TMDBAPIKey), committed to git (first in 936d503). `TMDBService.swift` comment says it is "never hardcoded... added outside source control", which is false | Should fix. Any client-side key is extractable from the shipped app; accept that, but keep it out of the repo and rotate it. |
| Image and data caching limits | Posters downloaded once to Documents/Posters for offline use | UNSURE: TMDB terms restrict long-term storage of data/images. Read the caching clause. |
| Movie data is not from TMDB-sourced user-specific credit (JustWatch etc.) | Not used | OK. |
| No use of TMDB data to build a competing database | Only the user's own logs saved | OK. |

---

## 3. App Store requirements

### 3.1 Guideline 1.2, user generated content
Bloom lets friends see each other's notes, photos, voice memos, display names, usernames, avatars, comments and replies. That is UGC.

| 1.2 requirement | Today | Missing |
|---|---|---|
| Filter objectionable material | None | No filtering or moderation |
| Report content and users, with timely response | None. VERIFIED: no "report" feature in any Swift file | Report on note, comment, profile |
| Block abusive users | None. Only "remove friend" (deletes friendship, `FriendService.swift` 169-174) | Block, with the blocked user's content hidden and requests refused |
| Published contact info | None in the app | Support email in app and App Store Connect |
| Terms that forbid objectionable content | None | Terms of Use with acceptance at sign up |
| Remove content the user posts / remove offenders | Owner can delete own notes and comments (`NoteDetailSheet`) | An admin route to remove a user and content (you, via Firebase console, is acceptable if documented) |

Mitigating: content is only visible to accepted friends, not public. Apple still expects report and block for any UGC and friend feature. **Must fix.** APPLE GUIDELINES 1.2.

### 3.2 Guideline 5.1.1
- **(i) Privacy policy:** none in app, none linked. Must be in App Store Connect and inside the app. **Must fix.**
- **(v) In-app account deletion:** not present. VERIFIED: no `delete()` on the Firebase user, no "Delete account" in `SettingsView.swift`. Sign out only. **Must fix.** Deleting needs: reauthentication (Firebase `requiresRecentLogin`), `user.delete()`, removal of Firestore data (see section 7), local store file and caches, and local notifications.
- **(ii) Consent:** no terms or privacy acceptance on sign up. **Must fix.**
- **(iii) Data minimisation:** reasonable. Phone is optional (email path exists).
- **(iv) Access:** Permissions can be declined; contact search and camera work without the others. OK.
- **Contacts:** Guideline 5.1.1(iv)/(ix) and 5.1.2: contact numbers are sent to your server as query values. Disclose in policy and permission text.

### 3.3 Guideline 5.1.2 data use and sharing
No data is sold or shared for ads. Data goes to Google (Firebase) as processor and TMDB (search text only). Must be disclosed in the policy and nutrition label. Should fix (drafted in docs/legal).

### 3.4 Guideline 4.8 login services
Bloom uses its own email/phone accounts through Firebase and no Google/Facebook/Apple social login. Sign in with Apple is therefore **not applicable** (APPLE GUIDELINES 4.8; re-read the current wording because it changed in 2024). If you add any third party social login, this changes.

### 3.5 Guideline 2.1 completeness
- No "coming soon" text found; no lorem ipsum. VERIFIED by grep.
- `BloomApp.swift` lines 14-16: a production `print` loop over fonts. CLAUDE.md forbids print calls. **Should fix** (debug code).
- Sample data exists only in previews (`LibraryView.swift` ~464, `FriendProfileView.swift` ~323, `#if DEBUG` in `GardenRealityView.swift` 876). Acceptable by your own rule. UNSURE: LibraryView line 464 is inside a preview builder; confirm it is not compiled in release.
- App Review will need a **demo account**: phone sign up needs SMS, which reviewers cannot receive. Provide an email/password account in App Review notes, with a second account to see friends. **Must fix** (rejection risk, 2.1).
- No password reset flow (VERIFIED: no `sendPasswordReset`). A user who forgets an email password is locked out. Should fix.
- Firebase backend must be live and the Firestore rules deployed in production mode before review.
- The deployment target is iOS 26.5 (VERIFIED `project.pbxproj`) and test targets 27.0. Confirm the audience can run it. Nice to have.
- The App icon is present (`Bloom Logo.png`, dark variant); tinted variant has no file in `Contents.json`. Nice to have.
- About page shows "Student ID 34942238", "FIT3178", "Monash University" (`AppInfo.swift`). For a public release this exposes a student ID. **Should fix** (privacy and perception, and check Monash IP policy, see questions).

### 3.6 Age rating questionnaire (answers to give, verify against current form)
- User generated content / unrestricted web access: UGC yes (private to friends), web access no.
- Messaging/social features between users: yes (comments).
- Violence, sexual content, profanity, gambling, horror, alcohol: none produced by the app. Movie titles come from TMDB (`include_adult=false` is set, VERIFIED `TMDBService.swift`), but TMDB titles and posters can include mature films. Answer honestly about mature themes in third party content. UNSURE.
- Apple's rating will likely land at 13+ or higher because of UGC. You want 16+ as a minimum age: Apple's rating tiers (check current ones) may not include 16+ exactly; enforce 16 in your Terms and sign up screen. LAW: see section 8.

### 3.7 App Privacy Details (nutrition label draft)
Verify each row in App Store Connect and against Firebase's own data disclosure page.

| Data type | Collected | Linked to user | Used for tracking | Purpose |
|---|---|---|---|---|
| Contact info: Email address | Yes (email sign ups, held by Firebase Auth) | Yes | No | App functionality |
| Contact info: Phone number | Yes (phone sign ups, stored in Firestore too) | Yes | No | App functionality |
| Contact info: Name (display name) | Yes | Yes | No | App functionality |
| Contacts | Yes, see note | UNSURE | No | App functionality |
| User content: Photos | Yes (note photos, avatar) | Yes | No | App functionality |
| User content: Audio data | Yes (voice memos) | Yes | No | App functionality |
| User content: Other user content | Yes (notes, comments, reactions, circles, reviews are device only) | Yes | No | App functionality |
| Identifiers: User ID | Yes (Firebase uid, username) | Yes | No | App functionality |
| Usage data: Product interaction | Yes (streaks, last post date) | Yes | No | App functionality |
| Search history | TMDB search text goes to TMDB, not linked to a user | No | No | App functionality. UNSURE |
| Diagnostics, device ID, IP | UNSURE: Firebase SDKs may send IP address and installation IDs. Check Firebase's privacy documentation | UNSURE | No | App functionality |
| Location, health, financial, browsing, purchases | No | n/a | n/a | n/a |

Contacts note: Apple counts data as "collected" if it leaves the device and is retained beyond real time processing. Normalised numbers are query values; Firebase request logs may retain them. UNSURE, lean towards declaring.

Tracking: **No**. Data linked to tracking: none.

### 3.8 Privacy manifest and encryption
- **PrivacyInfo.xcprivacy:** needed. No manifest in the project (VERIFIED: none in `git ls-files`). The app calls UserDefaults (`@AppStorage` and `UserDefaults` in AccountDefaults, BloomApp, ContentView, Settings views), a required-reason API: declare `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1`. Grep found no use of file timestamp, disk space, system boot time or keyboard APIs in app code (VERIFIED grep). Declare `NSPrivacyTracking` false, no tracking domains, and collected data types matching the table above. Firebase 12 ships its own manifests (verify in the archive's privacy report: Product > Archive > Generate Privacy Report). **Must fix** (App Store Connect warns or rejects for missing declarations).
- **ITSAppUsesNonExemptEncryption:** not set (VERIFIED: absent from `Info.plist` and build settings). Bloom uses only HTTPS/TLS through Apple's and Firebase's libraries. That normally qualifies as exempt, so set it to `NO` to skip the export prompt on every upload. APPLE: verify against Apple's export compliance page. For worldwide distribution, some countries (for example France) have extra rules for apps using encryption: UNSURE, LAWYER if you want certainty. **Should fix.**

---

## 4. Consent and permissions

| Permission | Wording (VERIFIED `project.pbxproj`) | Honest and specific? | Requested in context? |
|---|---|---|---|
| Camera | "Bloom uses the camera so you can take a photo to add to a note." | Yes | Yes, when Take photo is tapped (`CameraPicker.swift` 45) |
| Microphone | "Bloom records voice memos you attach to your notes." | Yes | Yes, first record press (AVAudioRecorder) |
| Contacts | "Bloom checks your contacts to help you find friends who are already using the app." | Mostly. Should say phone numbers are sent to Bloom's server to be matched | Yes, only on tapping contact search (`FriendService.swift` 101) |
| Photos | None needed. PhotosPicker is out of process | n/a | n/a |
| Notifications | Runtime prompt only | n/a | Yes: from the Settings card and reminder toggle (`SettingsNotificationsView.swift` 100, 190), never at launch (README/CLAUDE.md, VERIFIED no launch call) |
| Tracking, location | Not used | n/a | n/a |

Contacts: iOS 18+ limited access applies; code handles `.limited` in status display only. Nice to have.

**Sign up:** VERIFIED in `SignUpView.swift`: no link to Terms of Use or Privacy Policy, no statement of minimum age (16), no age confirmation. **Must fix.** The sign up footer text also does not say that the phone number will be stored and searchable by contacts.

**Notification flow:** Local notifications only, delegate set in `NotificationAppDelegate`. Reminder prompt and Settings card ask in context. Alerts for friend activity only fire while Bloom is running (CLAUDE.md). Consent wording in Settings should say so; README already does. OK.

---

## 5. Claims and content

| Claim (location) | Check | Verdict |
|---|---|---|
| "Bloom is a private journal" (`AppInfo.aboutText`, README title) | Notes are private only until shared. Backup is in Firestore, readable by the developer in the console, and Firebase is not end to end encrypted | Soften: say "private by default", not "private" alone. Should fix. |
| "Notes are saved on your device first and backed up privately" | Backup path is owner-only per README, but rules unverified | UNSURE until rules read. |
| "friends only see the notes you share" / "friends see only the notes you share from today and your pinned notes" | App-side filter only. README itself admits rules let accepted friends read every shared note. A modified client can read older shared notes | Overstates. Must fix wording, or fix rules (`createdAt` bound or `isPinned`). VERIFIED: README, `FriendJournalService.swift`. |
| "Only you can see your circles." | Circles are at `users/{uid}/circles`; rules unverified | UNSURE. Probably true if rules limit that path to owner. |
| Contact matching comment: "nothing is uploaded... an arbitrary number can't be probed this way" (`FriendService.swift` 92-95) | Numbers are sent as query values. If rules let any signed in user query `users` by `phoneNumber` (they must, for this feature to work), anyone can test whether any phone number is registered, and read the matched profile | Overstates. Must fix or verify rules. Phone numbers also sit in `users/{uid}` readable by whoever can read that doc. |
| "Enforced... friends only" friend requests | Rules unverified | UNSURE |
| README "Photos... 120 tests / 134 tests" | You say 134, README says 120 + 14 UI. Not a user-facing claim | Ignore. |
| "Generative AI tools (Claude by Anthropic, and Figma Make) were used..." (`AppInfo.generativeAINote`) | Honest | OK. Keep. |
| TMDB attribution | See section 2 | Logo missing |
| Marketing "a shared garden of memories" | Fine | OK |
| Fake reviews or testimonials | None found | OK |
| Placeholders, TODO, "coming soon" | None found. A `print` in `BloomApp` | See 3.5 |

**Assets**

| Asset | Source / licence | Risk |
|---|---|---|
| App icon `Bloom Logo.png`, `Bloom Logo Dark.png` | UNSURE: who made it? If AI generated or from a stock site, confirm you can use it commercially | Question 4 |
| `TMDBLogo.svg` | TMDB brand asset, usable only under TMDB's attribution rules | Not shown (see above) |
| DM Sans (4 TTFs in `Bloom/Fonts`) | I believe SIL Open Font License 1.1 (Google Fonts). OFL allows bundling in apps but requires the licence text to accompany the font. Not in Acknowledgements, and `FirebaseLicenseText` is the only licence shown | Should fix: add DM Sans and OFL to Acknowledgements. Verify licence at fonts.google.com. |
| SF Symbols | Apple licence: for use in apps made for Apple platforms, not allowed as app icon or logo-like marks for your brand. `leaf.fill` is a large "badge" on `WelcomeView.swift` and in the About header; it works as a brand mark | Should fix. Apple's SF Symbols licence and HIG say symbols can't be used in app icons or logos and some (Apple products) are restricted. Replace the Welcome mark with your own artwork (for example the app icon) or confirm with the licence. APPLE GUIDELINES / SF Symbols licence, UNSURE on strictness. |
| Emoji in `NoteComposerView.swift` (quick emoji) | Apple Color Emoji system font, user inserts into their own note | Fine. CLAUDE.md says no emoji in UI text, but these are user content picks. |
| TMDB posters | Downloaded from `image.tmdb.org` and stored; shown in Library and notes. Sent to friends? Not uploaded. Posters are copyrighted by studios; TMDB licenses them for use via its API with attribution | UNSURE. Check TMDB terms on image use. LAWYER if you want certainty. |
| Sounds | Only `UNNotificationSound.default`. None bundled | OK |
| Figma wireframes | Your own | OK |
| Generative AI | AI assisted code and wireframes disclosed | Fine. Check whether Monash unit rules restrict publishing the work (question 6). |

---

## 6. Accessibility and forms

Counts are from grep and reading, not from running VoiceOver. Please test on device.

**Positives (VERIFIED):** Dynamic Type adaptations (`AuthMethodPicker` switches layout at accessibility sizes, `@ScaledMetric` in WelcomeView, previews at accessibility5), Reduce Motion handled in `WelcomeView`, 44 pt minimums on many buttons, error text pairs an icon with colour (`AuthErrorText`), 35 files use `accessibilityLabel`, tests use identifiers.

**Findings**
- Welcome and About use a decorative leaf; fine (`accessibilityHidden`).
- Many fixed `.font(.system(size:))` uses in three places (grep count 3): confirm they scale. Nice to have.
- `lineLimit(1)` in 5 places can truncate at large sizes. Test at accessibility5. Nice to have.
- Colour contrast not measured. Run the Sufficient Contrast skill or Xcode's Accessibility Inspector over `Theme.Colors` pairs (text secondary on cream background, tints) against 4.5:1 and 3:1. UNSURE.
- Icon only buttons: run a VoiceOver pass over Today's Notes quick attach icons, reaction buttons and the NoteDetail three dot menu. UNSURE.
- Plant status (blooming, wilting, dead) should be conveyed with text as well as colour in the Greenhouse list: check. UNSURE.

**Text fields (VERIFIED, `SignUpView`, `LogInView`, `PhoneVerificationView`)**

| Field | Issue |
|---|---|
| Display name | Has `.textContentType(.name)` and words capitalisation. No `.submitLabel`. |
| Username | No `.textContentType(.username)`, no `.autocorrectionDisabled()`. |
| Phone | `.phonePad` but no `.textContentType(.telephoneNumber)`. |
| Email | Keyboard and no-caps set; no `.textContentType(.emailAddress)` (log in: `.username`), no autocorrect off. |
| Password | `SecureField` with no `.textContentType(.newPassword)` (sign up) or `.password` (log in); blocks password autofill and strong password suggestion. Should fix. |
| SMS code | `.numberPad`, no `.textContentType(.oneTimeCode)`; iOS cannot offer the code from the keyboard. Should fix. |
| All | No `@FocusState`, no `.submitLabel`, no `.onSubmit`. Return on a hardware keyboard does nothing; Tab order is system default. Cmd+Return is not wired. Should fix. |
| Library, add friend | `.onSubmit(of: .search)` present. OK. |
| Today's Notes | Cmd+left and Cmd+right shortcuts exist. OK. |

Password minimum is 6 (Firebase default, form footer). Consider 8. Nice to have.

---

## 7. Security and data risks

- **GoogleService-Info.plist history.** The file is in `.gitignore` now but was committed in `afd7940` and removed in `f89fb6f` (VERIFIED `git log --diff-filter=AD`). The remote is Monash's GitLab (`git.infotech.monash.edu`). The Firebase API key in that file is not a secret in the Firebase model, but it must be restricted (iOS bundle ID restriction in Google Cloud console) and Firebase App Check should be enabled so the backend only serves your app. Should fix. If the repo is ever made public, rewrite history or treat the key as exposed.
- **TMDB key** committed in `Bloom/Info.plist` (VERIFIED). Rotate it and keep it in an xcconfig excluded from git. Should fix.
- **Firestore rules** are not versioned. Put `firestore.rules` in the repo and test with the emulator. Must fix before release. Questions the rules must answer:
  - Can an accepted friend read older shared notes? (README says yes.)
  - Can any signed in user list `users` and read `phoneNumber`? (Contact search suggests yes.)
  - Is `streaks/{uid}` readable by non-friends?
  - Can any signed in user write `activity` for any recipient (needed by `ActivityWriter`)? That allows spam into others' feeds and fake "accepted" or comment previews.
  - Can a user create a friendship for any pair, or accept on behalf of another?
  - Document size and field limits (photo 100 KB avatar, 800 KB audio): are they enforced server side? The 1 MB document cap applies.
  - Is `sharedNotes` still open? Remove it if unused (`SharingService.swift`).
- **Account deletion and retention.** Nothing is deleted when an account leaves. Firestore does not cascade delete subcollections. After "delete account" you must remove: `users/{uid}` and its subcollections (`notes`, `comments`, `reactions`, `photos`, `audio`, `avatar`, `circles`, `activity`), `friendships` involving the uid, `streaks/{uid}`, your comments and reactions left on friends' notes, your `activity` entries in others' feeds, and the Auth record. A Cloud Function ("Delete User Data" extension) is the usual approach. Also local store `Application Support/Bloom/<uid>.store`, covers, caches. Also decide retention for deleted notes (code deletes note, photo, audio, comments; `NoteSyncService.swift`) and Firebase backups. Must fix.
- **Abuse.** No block/report, no rate limits on friend requests or comments, no profanity filter in names. Covered in 3.1.
- **Email not verified.** Anyone can sign up with someone else's address; harmless now since email isn't shown, but it prevents recovery. Nice to have.
- **Phone enumeration** via contact queries (see claims). Consider hashing numbers, or a server function with rate limits. LAWYER/engineer.
- **Deep link `bloom://add/{uid}`** exposes a uid and opens an Add sheet; low risk. OK.
- **Local data not encrypted beyond iOS file protection.** Audio and covers in Documents; set file protection. Nice to have.
- **Minor:** `AuthService.createUserProfile` runs after `createUser`; if it fails the account exists with no profile (`SignUpView.submit`). Should fix.
- **Single point of failure:** you are the data controller for friends' data on a Monash/personal Firebase project. Confirm the Firebase project is owned by you personally or a legal entity, not a university account. Question 5.

---

## 8. Laws that might apply

I have not summarised any law whose detail I am unsure of. For each, the first step is the official source.

| Law | Why it might apply | Small developer treatment | Verify (official source) | Lawyer? |
|---|---|---|---|---|
| Privacy Act 1988 (Cth) and the Australian Privacy Principles | You are based in Victoria and handle personal information (contacts, photos, voice). | The Act has a "small business operator" exemption by turnover (I recall AUD 3 million). It has exceptions, and I believe ones apply for businesses that trade in personal information. Whether an individual or hobby app is covered at all is unclear to me. | OAIC (oaic.gov.au): small business exemption and exceptions; also recent amendments for children's privacy. | Yes |
| Online Safety Act 2021 (Cth) and eSafety codes; social media minimum age law (Online Safety Amendment (Social Media Minimum Age) Act 2024) | Bloom has friends, comments and sharing, and you chose a minimum age of 16. Whether Bloom counts as an "age-restricted social media platform" is not something I can decide. | Not known | eSafety Commissioner (esafety.gov.au): definition of age-restricted platforms, any exemptions, the industry codes, and complaint handling obligations. | Yes |
| Australian Consumer Law (Competition and Consumer Act 2010) | Misleading privacy or security claims in the app or App Store listing. | Applies to businesses of all sizes | accc.gov.au on misleading claims | Yes (claims) |
| GDPR (EU) | Worldwide distribution means EU users. GDPR applies when you offer services to people in the EU or monitor them. | No general exemption for small developers. Some record keeping duties are lighter under 250 staff but not removed | EUR-Lex; your EU data protection authority; Article 3 (scope), Article 8 (age of digital consent, varies by country 13-16), Articles 13-17 (information, access, erasure), Article 27 (EU representative), Chapter V (transfers to Google in the US) | Yes |
| UK GDPR and Data Protection Act 2018; the ICO Children's Code | UK users | Same as above. Children's code applies to services likely to be accessed by under 18s | ico.org.uk: scope, whether a 16+ service is still "likely to be accessed" by children, UK representative | Yes |
| CCPA / CPRA (California) | California users | It only covers businesses over a revenue or data volume threshold, and I do not remember the current figures | oag.ca.gov and cppa.ca.gov for current thresholds | Probably not, but confirm |
| COPPA (US) | Applies to online services directed at under 13s or that knowingly collect data from them. Your age limit is 16 | Not exempt | ftc.gov COPPA FAQ: "actual knowledge" and mixed audience rules, what to do if you learn of an under 13 account | Yes if unsure |
| Other US state privacy and age laws, other countries (for example Brazil LGPD, Canada PIPEDA, Singapore, Japan, South Korea) | Worldwide listing | Varies | Easiest control: choose countries in App Store Connect and only list where you have checked | Yes |
| Spam Act 2003 and SMS rules | Firebase sends the verification SMS, not you | n/a | Firebase terms | No |
| Apple Developer Program License Agreement, Firebase/Google Cloud terms, TMDB terms | Contractual, not law | n/a | The contracts themselves | Optional |

Also decide, with a lawyer, whether publishing as an individual or as a company: the legal entity name goes on the App Store listing and the privacy policy.

---

## 9. Drafts
Written to `docs/legal/PRIVACY_POLICY.md` and `docs/legal/TERMS_OF_USE.md`. Not wired into the app. Both state plainly that Bloom has no purchases and no cookies.

---

## 10. Prioritised to-do list

Effort: S under 2 hours, M half a day to a day, L several days.

### Must fix before release
| # | Item | Effort |
|---|---|---|
| 1 | In-app account deletion with reauthentication and full data erasure (client flow + Cloud Function or client batch) (5.1.1(v)) | L |
| 2 | Report content and report user, block user, hide blocked users' content (1.2) | L |
| 3 | Privacy policy and Terms of Use: finish drafts, host them at a public URL, link from sign up, Settings > About and App Store Connect (5.1.1(i), 1.2) | M |
| 4 | Sign up consent: Terms and Privacy links, "You must be 16 or older" statement or confirmation | S |
| 5 | Export Firestore rules, commit them, test them, close the gaps in section 7 (friends reading older notes, phone enumeration, `activity` writes) | L |
| 6 | Fix privacy claims: "friends only see today" is app-enforced, the contacts comment, "private" wording (App Store listing too) | S |
| 7 | Add `PrivacyInfo.xcprivacy` (UserDefaults CA92.1, collected data types) | S |
| 8 | Show the TMDB logo (move `TMDBLogo` into an `.imageset`) and re-read TMDB terms for commercial use and caching | S |
| 9 | App Review demo accounts (email based) and live production backend | S |
| 10 | App Privacy Details answers in App Store Connect (table in 3.7) and age rating questionnaire | S |

### Should fix
| # | Item | Effort |
|---|---|---|
| 11 | Remove production `print` in `BloomApp.swift` | S |
| 12 | Set `ITSAppUsesNonExemptEncryption` to NO (Info.plist, not the project file) | S |
| 13 | Rotate TMDB key, move out of Info.plist/git; restrict Firebase API key, enable App Check | M |
| 14 | Replace the `leaf.fill` brand mark on Welcome/About (SF Symbols licence) | S |
| 15 | Remove student ID, unit and university from About for release (or decide to keep) | S |
| 16 | Add DM Sans (OFL) to Acknowledgements | S |
| 17 | Text field traits: `.newPassword`, `.password`, `.oneTimeCode`, `.username`, `.emailAddress`, submit labels, focus order, return key | M |
| 18 | Password reset flow; create profile atomically with sign up | M |
| 19 | Contacts permission wording: say numbers are sent to Bloom's server | S |
| 20 | Content filtering for display names, usernames and comments, plus rate limits | M |
| 21 | Delete legacy `sharedNotes` code and collection if unused | S |

### Nice to have
| # | Item | Effort |
|---|---|---|
| 22 | VoiceOver, contrast and largest Dynamic Type pass with the specialist skills | M |
| 23 | Email verification, stronger password rule | S |
| 24 | File protection on local audio and covers | S |
| 25 | Tinted app icon variant file | S |
| 26 | Confirm lower iOS deployment target is wanted | S |

### Questions for you
1. Do you want to publish as an individual or a company, and will a support email other than your student address be used? (Student email may stop working after graduation.)
2. Is the Firebase project (`bloom-726b7`) owned by you personally, or by Monash? Which region is Firestore in?
3. Can you export the current Firestore rules and paste them (or add them to the repo)?
4. Who made the app icon, and was any asset AI generated?
5. Does Monash's unit policy or IP policy allow you to publish this work, and to publish it with your name?
6. Will the app stay free with no ads, purchases or subscriptions? (affects TMDB, Apple tax forms, consumer law.)
7. Should the age statement be a confirmation checkbox, a date of birth, or a notice only?
8. Which countries should the app be released in? Narrowing to Australia first reduces the legal list.
9. Which items from this list should I implement? (The prompt said "[list the numbers]" and the list was blank, so I changed no project files.)

## Five things to fix first
1. Account deletion that really erases data (item 1).
2. Report and block, with Terms that ban abuse (items 2, 3, 4).
3. Export and fix the Firestore rules, because the "today only" limit and contact search depend on them (items 5, 6).
4. Privacy policy hosted and linked, plus the privacy manifest and App Privacy answers (items 3, 7, 10).
5. TMDB logo, key and terms, plus an App Review demo account (items 8, 9, 13).

---

## Status after the compliance branch (2026-11-01)

Checked with: full Swift suite (216 passed), Firestore rules emulator tests (53 passed, 1 todo), app builds. Nothing here says Bloom is compliant with any law. "Done" means the change is in the code or docs. Items that need you, the Firebase console, App Store Connect or a lawyer are marked Manual.

### Must fix
| # | Item | Status | What is left |
|---|---|---|---|
| 1 | In-app account deletion | Done | Deploy rules and indexes first. Test with a throwaway email account and a phone account |
| 2 | Report and block | Done | Check `reports` in the console daily (docs/moderation.md). Deploy the rules, the report and block rules were once lost in a rewrite (76b6b05 restores them) |
| 3 | Privacy policy and Terms, linked in app | Partly | Pages written and hosted in `site/`, links in sign up and About. Deploy hosting. No lawyer has reviewed them (the Terms say so) |
| 4 | Sign up consent and age | Done | Box is checked when Sign Up is tapped, not by disabling the button |
| 5 | Firestore rules | Done | Deploy. Open: any signed in user can list `users` (username search needs it), usernames are not unique, the pin limit is app only |
| 6 | Overstated claims | Done | Check the App Store description and screenshots by hand |
| 7 | Privacy manifest | Done | Compare with Product, Archive, Generate Privacy Report |
| 8 | TMDB logo | Done | Re-read TMDB's terms for commercial use and image caching |
| 9 | App Review demo accounts | Partly | Instructions written, you create the two accounts |
| 10 | App Privacy and age rating answers | Partly | Drafted in docs/app-store-connect.md, you enter them |

### Should fix
| # | Item | Status | What is left |
|---|---|---|---|
| 11 | Remove production print | Done | |
| 12 | ITSAppUsesNonExemptEncryption | Done | |
| 13 | TMDB key out of the repo | Partly | Key now comes from the gitignored `Config/Secrets.xcconfig`. Rotate it (old key is in git history). Restrict the Firebase API key to the bundle id and enable App Check |
| 14 | SF Symbol brand mark | Done | |
| 15 | Student ID, unit, university in About | Decided to keep | |
| 16 | DM Sans licence | Partly | Acknowledged in the app. `DMSans-OFL.txt` is in the repo but not shown in the app |
| 17 | Text field traits and focus | Done | VoiceOver and hardware keyboard still need a hands on pass |
| 18 | Password reset, safe profile creation | Done | |
| 19 | Contacts wording | Replaced | Contact matching was removed instead |
| 20 | Content filtering and rate limits | Skipped by choice | Report and block only |
| 21 | Legacy sharedNotes | Partly | Code removed and rules closed. Delete the collection in the console |

### Nice to have
Not started: VoiceOver, contrast and largest Dynamic Type pass, email verification and a stronger password rule, file protection on local audio and covers, a tinted app icon file, the iOS 26.5 deployment target.
