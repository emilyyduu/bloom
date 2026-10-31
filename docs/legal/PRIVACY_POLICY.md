# Bloom Privacy Policy

> **DRAFT. Needs review before publishing.** Written from what the app does in code on 2026-10-31. It is not legal advice. Have a lawyer check it, fill every [PLACEHOLDER], and confirm the Firestore rules match it. Update it whenever the app changes.

Effective date: [PLACEHOLDER: date]

## Who we are
Bloom is made by Emily Du, based in Victoria, Australia ([PLACEHOLDER: individual or company name and address]).
Contact: eduu0005@student.monash.edu ([PLACEHOLDER: replace with a long term support email if you have one]).

## The short version
- Bloom has no purchases and no ads.
- Bloom has no cookies. It is a mobile app, not a website.
- Bloom does not use analytics or advertising trackers and does not track you across other apps or websites.
- Your notes are stored on your device first and backed up to your account in our database. They are shared with friends only when you choose.

## Minimum age
You must be at least 16 to use Bloom. We do not knowingly collect data from anyone younger. If you think a younger person has an account, contact us and we will delete it. [PLACEHOLDER: lawyer to confirm wording and whether further steps are needed.]

## What we collect and why

| What | Why | Where it is kept |
|---|---|---|
| Email address and password (if you sign up with email) | To sign you in | Firebase Authentication (Google) |
| Phone number (if you sign up with a phone) | To sign you in with a text code, and so friends can find you through their contacts | Firebase Authentication and our database |
| Display name and username | Shown to your friends; the username lets people search for you | Our database |
| Profile picture (optional) | Shown on your profile | Our database |
| Notes: text, dates, whether a note is a draft, shared or pinned | To run your journal, back it up and show it to friends you share with | Your device, and a backup in our database |
| Photos you attach to notes | Same as notes | Your device and our database (small compressed copy) |
| Voice memos (up to 60 seconds) | Same as notes | Your device and our database |
| Friend requests and friendships | To connect you with friends | Our database |
| Circles (private named groups of friends) | To choose whose plants you see. Only you can see them in the app | Our database |
| Streak (current count, last post date) | To grow your plant in the Shared Garden. Your friends can see it | Our database |
| Comments, replies and reactions | Social features on shared notes | Our database |
| Notification feed items (who did what, with a short preview) | To show your in-app notifications list | Our database |
| Movie and show log (rating, review, poster) | Your Library | Your device only. It is not backed up |
| Journal cover photos | Decoration | Your device only |
| Settings such as reminder time and appearance | To remember your choices | Your device only |

### Contacts
If you tap to find friends from your contacts, Bloom reads the phone numbers in your contacts on your device and sends those numbers to our database to see which belong to Bloom accounts. We do not store your contacts. Matches are shown to you. [PLACEHOLDER: confirm with Firebase logging settings whether queried numbers are logged and for how long.]

### Movie and show search
When you search the Library, your search words are sent to The Movie Database (TMDB) to get results. Posters are downloaded from TMDB. TMDB sees your IP address and the search words. Bloom does not send your name or account to TMDB. See TMDB's privacy policy: [PLACEHOLDER: TMDB privacy policy URL].

### Camera, microphone, notifications
These are optional. Bloom asks only when you use the feature. Photos you pick with the system photo picker are shared with Bloom only for the photos you choose.
Notifications are created by the app while it is running. Bloom does not send push notifications from a server. [PLACEHOLDER: update if you add push.]

## Who can see your information
- **Only you:** your drafts, notes you have not shared, circles, movie log, covers and settings.
- **Your accepted friends:** your display name, username, profile picture, streak and plant, and notes you mark as shared. In the app, friends see the notes you shared today and your pinned notes. [PLACEHOLDER: lawyer and developer to confirm. Today the database rules may let an accepted friend read older shared notes if they bypass the app. Fix the rules or change this sentence.]
- **Other Bloom users:** can find you by username and, if you signed up with a phone, by phone number match. They can send you a friend request. They see your display name, username and avatar in search results. [PLACEHOLDER: confirm with the Firestore rules.]
- **Us:** the developer can access the database through the Firebase console. We will only do this to run, secure and fix the service, or to act on a report or legal request.
- **Service providers:** Google (Firebase Authentication and Cloud Firestore) stores and processes account and backup data and sends sign in text messages. Google may process data in countries other than yours. TMDB receives search words as above.
- We do not sell your data and do not use it for advertising.

## Keeping your data
Your data stays until you delete it or delete your account. Deleting a note removes it from your device and from our database, along with its photo, voice memo and comments. [PLACEHOLDER: describe the account deletion feature once built, what is erased and how long backups take to clear.] Backups kept by Google may take [PLACEHOLDER: period] to expire.

## Your choices and rights
You can edit your profile, delete notes, stop sharing, remove friends and turn off permissions in iOS Settings. You can delete your account in the app [PLACEHOLDER: not yet built]. You can ask us to access, correct or delete your data at the email above. Depending on where you live (for example Australia, the EU or UK) you may have further rights, including to complain to a regulator. [PLACEHOLDER: lawyer to list rights and regulators, Privacy Act 1988 / GDPR / UK GDPR / CCPA as applicable.]

## Security
Data travels over encrypted connections and is stored in Google's cloud. It is not end to end encrypted, so we and Google's systems can technically access it. No system is perfectly secure.

## Changes
We will update this policy when the app changes and show the effective date above. [PLACEHOLDER: describe how you will notify users of material changes.]

## Contact
Emily Du, eduu0005@student.monash.edu
