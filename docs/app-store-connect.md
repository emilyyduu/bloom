# App Store Connect answers

Answers for the App Store Connect forms, written from the app as it stands on the `compliance` branch. Check each against the current form when you reach it, because Apple changes the wording. Anything marked UNSURE needs your decision or a lawyer.

## 1. App information

| Field | Answer |
|---|---|
| Name | Bloom |
| Primary category | Lifestyle (Productivity is also reasonable) |
| Price | Free, no in-app purchases |
| Availability | Australia only (App Store Connect, Pricing and Availability) |
| Privacy Policy URL | https://bloom-726b7.web.app/privacy (same as `LegalLinks.privacyPolicy` in the app) |
| Support URL | Not applicable for the unit submission. The support email is eduu0005@student.monash.edu, a student address that will expire |
| Terms of Use | https://bloom-726b7.web.app/terms (same as `LegalLinks.terms` in the app) |
| Copyright | 2026 Emily Du |
| Sign in required | Yes. Give the demo accounts from `docs/app-review-notes.md` |
| Contact for review | Emily Du, eduu0005@student.monash.edu (a student address that will expire). Phone: Not applicable for the unit submission |

Content rights: answer **Yes**, the app shows third party content (movie and TV data and posters from TMDB) and say you have the rights under TMDB's terms. UNSURE: re-read TMDB's terms for commercial use and image caching before answering.

Advertising Identifier (IDFA): **No**. The app does not use it.

Export compliance: `ITSAppUsesNonExemptEncryption` is set to NO in `Info.plist`. The app uses only standard encryption (HTTPS) from Apple and Firebase, which is normally exempt. UNSURE: confirm on Apple's export compliance page. Some other countries have extra rules, but you are releasing in Australia only. Ask a lawyer if you later widen the release.

## 2. App Privacy (the "nutrition label")

Choose **Yes, we collect data from this app**. Tracking: **No**, for every type. All data below is **linked to the user** (it is tied to their account) unless stated.

| Data type | Collected | Linked to user | Used to track | Purpose |
|---|---|---|---|---|
| Contact info: Email address | Yes (email sign ups, kept by Firebase Authentication) | Yes | No | App functionality |
| Contact info: Phone number | Yes (phone sign ups, kept by Firebase Authentication only) | Yes | No | App functionality |
| Contact info: Name | Yes (the display name the user chooses) | Yes | No | App functionality |
| User content: Photos or videos | Yes (note photos, profile picture) | Yes | No | App functionality |
| User content: Audio data | Yes (voice memos) | Yes | No | App functionality |
| User content: Other user content | Yes (notes, comments, reactions, circles, reports and blocks) | Yes | No | App functionality |
| Identifiers: User ID | Yes (account id and username) | Yes | No | App functionality |
| Usage data: Product interaction | Yes (streak and last post date) | Yes | No | App functionality |
| Search history | The movie and show search words are sent to TMDB. TMDB is not given a name or account. UNSURE whether Apple counts this as collected | No | No | App functionality |
| Diagnostics, Device ID, Location, Contacts, Health, Financial, Browsing, Purchases, Sensitive info | No | n/a | n/a | n/a |

Changes from the audit draft: **Contacts is no longer collected**, because contact matching was removed. Phone number is now kept only in Firebase Authentication.

UNSURE, decide before answering:
- Firebase may receive technical data such as IP address and installation ids. Read Google's Firebase privacy documentation and answer **Diagnostics** or **Device ID** to match.
- Declaring tracking domains or analytics: none are used.

The same data types are in `Bloom/PrivacyInfo.xcprivacy`. Keep the two in step. Before the first upload, in Xcode choose Product, Archive, then Generate Privacy Report, and compare it with this table.

## 3. Age rating questionnaire

Answer with what the app does. Apple's form changes, so match each question to the nearest topic below.

| Topic | Answer |
|---|---|
| Violence, sexual content or nudity, profanity or crude humour, horror or fear, alcohol, tobacco or drug use, gambling, contests | **None** or **Never**. The app itself shows none |
| Medical or treatment information, health or wellness topics | None |
| Mature or suggestive themes | Infrequent at most. Users' own notes are not controlled, and TMDB titles and posters can include mature films. The search sets `include_adult=false`. UNSURE: choose the answer that matches your comfort, and be honest |
| User generated content, or social features where users share content | **Yes**, with controls: report content, block users, remove friends, and notes are visible only to accepted friends |
| Messaging, chat or contact between users | **Yes** (comments, replies, reactions between friends) |
| Unrestricted web access | **No**. The app has no web browser. Links open in Safari |
| Parental controls, age assurance | None built in. Users confirm they are 16 or older at sign up |
| Gambling, loot boxes, in-app purchases | No |

Expected result: Apple will likely compute **13+** or higher because of user generated content and messaging. Your minimum age is 16. If App Store Connect lets you raise the rating, set it to **16+** so it matches the Terms. UNSURE: Apple may not offer an exact 16+ in every region or form, so check. Whatever the rating, the Terms and the sign up box state 16.

## 4. TestFlight

1. Archive in Xcode, upload to App Store Connect, wait for processing.
2. Internal testing (people on your App Store Connect team, up to 100): no review needed. Start here.
3. External testing needs **Beta App Review**. Fill in:
   - Beta App Description: Bloom is a shared journaling app. Write notes, share them with friends, grow a garden.
   - What to test: sign up with an email, add a friend (use the second tester), share a note, comment, then try Report, Block and Delete account.
   - Feedback email: eduu0005@student.monash.edu
   - Test account and notes: reuse `docs/app-review-notes.md`.
4. Before the first external build, deploy the Firestore rules and indexes (README, "Firestore rules"). Without the indexes, Delete account fails.
5. Testers in Australia can use their own phone for SMS sign in. Others should use email.

## 5. Before pressing Submit for Review

- `Bloom/Core/Utilities/LegalLinks.swift` already points at the hosted Terms and Privacy pages (the `site` folder). Check both URLs open, and that `site/` still matches `docs/legal/*`.
- The legal pages have no placeholders. They have not been reviewed by a lawyer.
- Screenshots and description must not claim anything the app does not do. Do not call the app "private" without saying backups are stored with Google and are not end to end encrypted.
- Rotate the TMDB key, since the old one is in git history.
