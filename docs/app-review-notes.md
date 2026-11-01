# App Review notes (paste into App Store Connect, "App Review Information")

This file is the text to give Apple's reviewers. Nothing here has credentials in it on purpose: the two demo accounts are set up with the steps below, and their details are supplied separately in the submission notes, never in this repo.

## Before you submit: set up the demo accounts

Reviewers cannot receive SMS codes, so give them email and password accounts. Use two, so they can see friends.

1. Install the build that will be submitted, with the production Firebase project and the deployed rules (see README, "Firestore rules").
2. Sign up account A with an email and password, display name "Review One", username `bloomreview1`. Tick the age and terms box.
3. Sign up account B with a second email, display name "Review Two", username `bloomreview2`.
4. From A, open the Profile tab, tap the friend count to open Friends, tap the Add friend button (person with a plus), search `bloomreview2`, and send a request. On B, open Notifications and accept it.
5. On A, add two or three ordinary notes (one with a photo, one with a voice memo) and share them with friends (Settings, Privacy, Share new notes with friends, or share each from its menu). Pin one.
6. On B, add a note and share it, and add a comment on one of A's notes.
7. Sign in as each account once on a real device to check Home, Greenhouse and Notifications all look right.
8. Keep both accounts signed out when you submit. Do not delete them while the review is open.

Keep the credentials out of the repo. They are supplied separately in the submission notes.

## Text for the "Notes" box

Bloom is a journaling app for people aged 16 and over. You write short notes through the day. They are saved on the device and backed up to the user's own account. Users can share notes with accepted friends, who can react and comment.

SIGN IN
Bloom offers sign in by phone number (an SMS code) or by email and password. Because you cannot receive SMS, please use the email demo accounts:
- Account A and Account B: two email accounts, with the email and password for each supplied separately in the submission notes.
They are already friends, so Home, Notifications, the Greenhouse and friend profiles have content. Sign out is in Profile tab, Settings.

USER GENERATED CONTENT (guideline 1.2)
- Users can see only people they have accepted as friends, plus a username search that shows a display name, username and picture.
- Report: on any friend's note (the ... menu at the top right of the note), on any comment by someone else (the ... button on the comment), and on any profile (the ... menu on a friend's profile). Choose a reason, add details if wanted, and Send.
- Block: from the same menus. Blocking ends the friendship, stops that person sending requests and hides what they write. Manage blocked people in Profile tab, Settings, Privacy, Blocked people.
- Reports are read in the Firebase console and handled within 3 days where possible, and the developer acts on them (removes content or disables the account). Reports are kept after an account is deleted for as long as needed. Contact: eduu0005@student.monash.edu, a student address that will expire (also in Settings, About, Contact the developer).
- Terms of Use and Privacy Policy links are on the sign up screen and in Settings, About. Users must tick that they are 16 or older and agree before signing up.

ACCOUNT DELETION (guideline 5.1.1(v))
Profile tab, Settings, Account, Delete account. The user confirms their password, then confirms deletion. This erases the account and its data from the backend and the device.

PERMISSIONS
- Camera: only when the user taps Take photo in a note.
- Microphone: only when the user records a voice memo.
- Notifications: asked from Profile tab, Settings, Notifications (never at launch).
- Bloom does not request access to contacts, location or tracking.

THIRD PARTY
- Accounts, backup and sharing use Google Firebase (Authentication and Cloud Firestore).
- Movie and TV search uses The Movie Database (TMDB) API. This product uses the TMDB API but is not endorsed or certified by TMDB. The attribution and logo are in Settings, About.
- Bloom has no ads, no analytics, no in-app purchases and does not track users.

NOTES ON BEHAVIOUR
- Friends see notes a user shares from today, and any they pin.
- The daily reminder is a local notification the user turns on in Settings.
- The Greenhouse tab shows a 3D garden (RealityKit). It needs at least one friend to show other plants.

Contact for review questions: Emily Du, eduu0005@student.monash.edu (a student address that will expire). Phone: Not applicable for the unit submission.
