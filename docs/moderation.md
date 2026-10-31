# Reviewing reports and handling abuse

Bloom lets people report a note, a comment or a person, and block people. Reports are stored in Firestore. The app cannot read them back. You review them in the Firebase console. App Review expects abuse reports to be acted on promptly, so check this at least once a day while the app is live, and record how fast you respond.

## Where reports are

1. Open the Firebase console, project **bloom-726b7**, then **Firestore Database**, then **Data**.
2. Open the top level collection **reports**. There is one document per report.
3. The document id is `reporterUID_kind_targetId`, for example `abc123_comment_9f2e`. A person can report the same thing only once.

| Field | Meaning |
|---|---|
| `kind` | `note`, `comment` or `user` |
| `reason` | `spam`, `harassment`, `inappropriate` or `other` |
| `details` | What the reporter typed (optional, up to 500 characters) |
| `contentPreview` | The text the reporter saw (up to 500 characters). Written by the reporter's app, so treat it as a lead and check the real content |
| `reporterUID` | Who reported. Do not tell the reported person |
| `reportedUID` | The person who wrote the note or comment, or the reported profile |
| `noteOwnerUID`, `noteId` | Where a note or comment lives |
| `commentId` | The comment, for `kind` = `comment` |
| `createdAt` | When it was sent |

To sort or filter, use the filter bar in the console, for example `createdAt` descending.

## Finding the content

- **note:** `users/{noteOwnerUID}/notes/{noteId}`. A photo is at `users/{noteOwnerUID}/photos/{noteId}` and a voice memo at `users/{noteOwnerUID}/audio/{noteId}`.
- **comment:** `users/{noteOwnerUID}/notes/{noteId}/comments/{commentId}`
- **user:** `users/{reportedUID}` (display name and username), and `users/{reportedUID}/avatar/current` for the picture.

## What to do

1. Read the report and look at the real content.
2. Decide:
   - **Not a problem:** do nothing to the content.
   - **Remove the content:** delete the comment document, or the note document (and its photo and audio documents).
   - **Remove the person:** in the console, **Authentication**, **Users**, find them by uid, and choose **Disable account**. They cannot sign in again. A session they already have can last up to an hour. Then delete their `users/{uid}` profile document (and `users/{uid}/avatar/current` if the picture is the problem), so friends no longer see them.
3. Record what you did on the report document itself. In the console add the fields `status` (`open`, `actioned` or `no action`), `action` (a short sentence) and `reviewedAt` (timestamp). The app cannot see or change reports, so these are only for you.
4. If the content is illegal (for example it endangers a child) do not just delete it. Keep a copy of the report, and take advice about reporting it. In Australia the eSafety Commissioner takes reports at esafety.gov.au. [PLACEHOLDER: confirm with a lawyer.]

## Limits to know about

- There is no email or push alert when a report arrives. Checking the **reports** collection is the only way to see them.
- A reporter or reported person is never told about the outcome by the app. If you want to reply to a reporter, you have their uid, not their email. Look the uid up in Authentication.
- Blocking is private. The blocked person is not told. It removes any friendship, so they can no longer read the blocker's notes, and the rules stop them sending a new friend request.
- Reports hold personal information (uids, a preview of what was written). Delete resolved reports after a set time and say how long in the privacy policy. [PLACEHOLDER: choose a retention period, ask a lawyer.]
- The contact address shown to users is eduu0005@student.monash.edu. Use an address you will still have once you graduate. [PLACEHOLDER]
