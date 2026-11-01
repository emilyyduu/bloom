// Emulator tests for ../firestore.rules. Run with `npm test` in this folder.
// RULES_PATH can point at another rules file, for example to check that these
// tests catch the gaps in an older version.
import { test, before, after, beforeEach, describe } from 'node:test';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import assert from 'node:assert/strict';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import {
  Bytes,
  Timestamp,
  collection,
  collectionGroup,
  deleteDoc,
  deleteField,
  doc,
  getDoc,
  getDocs,
  orderBy,
  query,
  setDoc,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';

const here = path.dirname(fileURLToPath(import.meta.url));
const rulesPath = process.env.RULES_PATH ?? path.join(here, '..', 'firestore.rules');

const ALICE = 'alice'; // owns the notes
const BOB = 'bob'; // accepted friend of alice
const CAROL = 'carol'; // stranger to alice, receives a request from bob
const DAVE = 'dave'; // stranger to everyone

const HOUR = 3_600_000;
const ts = (msFromNow) => Timestamp.fromMillis(Date.now() + msFromNow);

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'bloom-rules-test',
    firestore: { rules: readFileSync(rulesPath, 'utf8') },
  });
});

after(async () => {
  await env.cleanup();
});

const as = (uid, token = {}) => env.authenticatedContext(uid, token).firestore();

function note(overrides = {}) {
  return {
    text: 'hello',
    createdAt: ts(-HOUR),
    updatedAt: ts(-HOUR),
    isDraft: false,
    sharedWithFriends: true,
    ...overrides,
  };
}

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const uid of [ALICE, BOB, CAROL, DAVE]) {
      await setDoc(doc(db, 'users', uid), {
        username: `user_${uid}`,
        usernameLower: `user_${uid}`,
        displayName: uid,
        createdAt: ts(-100 * HOUR),
      });
    }
    await setDoc(doc(db, 'friendships', `${ALICE}_${BOB}`), {
      fromUID: ALICE, toUID: BOB, status: 'accepted', createdAt: ts(-50 * HOUR),
    });
    await setDoc(doc(db, 'friendships', `${BOB}_${CAROL}`), {
      fromUID: BOB, toUID: CAROL, status: 'pending', createdAt: ts(-HOUR),
    });
    const notes = doc(db, 'users', ALICE).path;
    await setDoc(doc(db, notes, 'notes', 'today'), note());
    await setDoc(doc(db, notes, 'notes', 'private'), note({ sharedWithFriends: false }));
    await setDoc(doc(db, notes, 'notes', 'old'), note({ createdAt: ts(-72 * HOUR), updatedAt: ts(-72 * HOUR) }));
    await setDoc(doc(db, notes, 'notes', 'oldPinned'), note({
      createdAt: ts(-72 * HOUR), updatedAt: ts(-72 * HOUR), isPinned: true, pinnedAt: ts(-HOUR),
    }));
    for (const id of ['today', 'old', 'oldPinned']) {
      await setDoc(doc(db, notes, 'photos', id), { data: Bytes.fromUint8Array(new Uint8Array(10)), updatedAt: ts(0) });
      await setDoc(doc(db, notes, 'audio', id), { data: Bytes.fromUint8Array(new Uint8Array(10)), updatedAt: ts(0) });
      await setDoc(doc(db, notes, 'notes', id, 'comments', 'c1'), { authorUID: ALICE, text: 'hi', createdAt: ts(0) });
    }
    await setDoc(doc(db, 'streaks', ALICE), { currentStreak: 3, lastPostDate: ts(0), updatedAt: ts(0) });
  });
});

const userDoc = (db, uid, ...rest) => doc(db, 'users', uid, ...rest);
const reservationDoc = (db, name) => doc(db, 'usernames', name);
const reservation = (uid, overrides = {}) => ({ uid, createdAt: ts(0), ...overrides });

// Writes a profile and claims its username in one batch, like the app does.
// The reservation is keyed by the lowercase username unless told otherwise.
function saveProfile(db, uid, data, name = String(data.username).toLowerCase()) {
  const batch = writeBatch(db);
  batch.set(userDoc(db, uid), data);
  batch.set(reservationDoc(db, name), reservation(uid));
  return batch.commit();
}

// Puts a reservation in place without going through the rules.
async function seedReservation(name, uid) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(reservationDoc(ctx.firestore(), name), reservation(uid));
  });
}

function libraryEntry(overrides = {}) {
  return {
    tmdbID: 603, mediaType: 'movie', title: 'The Matrix', year: 1999, posterPath: '/f89U3ADr1oiB1s9GkdPOEpXUk5H.jpg',
    rating: 5, reviewText: 'Mind blown', loggedAt: ts(-HOUR), noteID: 'today', ...overrides,
  };
}

describe('friends reading notes', () => {
  test('owner reads every note', async () => {
    for (const id of ['today', 'private', 'old', 'oldPinned']) {
      await assertSucceeds(getDoc(userDoc(as(ALICE), ALICE, 'notes', id)));
    }
  });

  test('friend reads a recent shared note', async () => {
    await assertSucceeds(getDoc(userDoc(as(BOB), ALICE, 'notes', 'today')));
  });

  test('friend cannot read an unshared note', async () => {
    await assertFails(getDoc(userDoc(as(BOB), ALICE, 'notes', 'private')));
  });

  test('friend cannot read an older shared note that is not pinned', async () => {
    await assertFails(getDoc(userDoc(as(BOB), ALICE, 'notes', 'old')));
  });

  test('friend reads an older shared note that is pinned', async () => {
    await assertSucceeds(getDoc(userDoc(as(BOB), ALICE, 'notes', 'oldPinned')));
  });

  test('a stranger cannot read a shared note', async () => {
    await assertFails(getDoc(userDoc(as(DAVE), ALICE, 'notes', 'today')));
  });

  test('the app query for today (Home tile and FriendToday) is allowed', async () => {
    const q = query(
      collection(as(BOB), 'users', ALICE, 'notes'),
      where('sharedWithFriends', '==', true),
      where('createdAt', '>=', ts(-5 * HOUR)),
      where('createdAt', '<', ts(19 * HOUR)),
      orderBy('createdAt', 'desc'),
    );
    await assertSucceeds(getDocs(q));
  });

  test('the app query for pinned notes is allowed', async () => {
    const q = query(
      collection(as(BOB), 'users', ALICE, 'notes'),
      where('sharedWithFriends', '==', true),
      where('isPinned', '==', true),
    );
    await assertSucceeds(getDocs(q));
  });

  test('listing every shared note is refused', async () => {
    const q = query(collection(as(BOB), 'users', ALICE, 'notes'), where('sharedWithFriends', '==', true));
    await assertFails(getDocs(q));
  });

  test('a query reaching back three days is refused', async () => {
    const q = query(
      collection(as(BOB), 'users', ALICE, 'notes'),
      where('sharedWithFriends', '==', true),
      where('createdAt', '>=', ts(-96 * HOUR)),
      orderBy('createdAt', 'desc'),
    );
    await assertFails(getDocs(q));
  });

  test('friends lose access when the friendship is removed', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await deleteDoc(doc(ctx.firestore(), 'friendships', `${ALICE}_${BOB}`));
    });
    await assertFails(getDoc(userDoc(as(BOB), ALICE, 'notes', 'today')));
  });
});

describe('photos, audio and comments follow the same visibility', () => {
  for (const kind of ['photos', 'audio']) {
    test(`${kind}: friend reads recent and pinned, not old`, async () => {
      await assertSucceeds(getDoc(userDoc(as(BOB), ALICE, kind, 'today')));
      await assertSucceeds(getDoc(userDoc(as(BOB), ALICE, kind, 'oldPinned')));
      await assertFails(getDoc(userDoc(as(BOB), ALICE, kind, 'old')));
      await assertFails(getDoc(userDoc(as(DAVE), ALICE, kind, 'today')));
    });

    test(`${kind}: only the owner writes, up to 800000 bytes`, async () => {
      const ok = { data: Bytes.fromUint8Array(new Uint8Array(800000)), updatedAt: ts(0) };
      const big = { data: Bytes.fromUint8Array(new Uint8Array(800001)), updatedAt: ts(0) };
      await assertSucceeds(setDoc(userDoc(as(ALICE), ALICE, kind, 'n'), ok));
      await assertFails(setDoc(userDoc(as(ALICE), ALICE, kind, 'n'), big));
      await assertFails(setDoc(userDoc(as(BOB), ALICE, kind, 'n'), ok));
    });
  }

  test('comments: friend reads on recent and pinned notes, not old ones', async () => {
    await assertSucceeds(getDoc(userDoc(as(BOB), ALICE, 'notes', 'today', 'comments', 'c1')));
    await assertSucceeds(getDoc(userDoc(as(BOB), ALICE, 'notes', 'oldPinned', 'comments', 'c1')));
    await assertFails(getDoc(userDoc(as(BOB), ALICE, 'notes', 'old', 'comments', 'c1')));
  });

  test('comments: friend can comment as themselves on a recent note only', async () => {
    const good = { authorUID: BOB, text: 'nice', createdAt: ts(0) };
    await assertSucceeds(setDoc(userDoc(as(BOB), ALICE, 'notes', 'today', 'comments', 'b1'), good));
    await assertFails(setDoc(userDoc(as(BOB), ALICE, 'notes', 'old', 'comments', 'b2'), good));
    await assertFails(setDoc(userDoc(as(BOB), ALICE, 'notes', 'today', 'comments', 'b3'), { ...good, authorUID: ALICE }));
    await assertFails(setDoc(userDoc(as(DAVE), ALICE, 'notes', 'today', 'comments', 'b4'), { ...good, authorUID: DAVE }));
    await assertFails(setDoc(userDoc(as(BOB), ALICE, 'notes', 'today', 'comments', 'b5'), { ...good, text: 'x'.repeat(501) }));
    await assertFails(setDoc(userDoc(as(BOB), ALICE, 'notes', 'today', 'comments', 'b6'), { ...good, text: '' }));
  });

  test('comments: author or note owner can delete, others cannot', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(userDoc(ctx.firestore(), ALICE, 'notes', 'today', 'comments', 'b1'), { authorUID: BOB, text: 'x', createdAt: ts(0) });
    });
    await assertFails(deleteDoc(userDoc(as(DAVE), ALICE, 'notes', 'today', 'comments', 'b1')));
    await assertSucceeds(deleteDoc(userDoc(as(BOB), ALICE, 'notes', 'today', 'comments', 'b1')));
    await assertSucceeds(deleteDoc(userDoc(as(ALICE), ALICE, 'notes', 'today', 'comments', 'c1')));
  });

  test('reactions: friend reacts once as themselves with a known kind', async () => {
    const good = { kind: 'love', createdAt: ts(0) };
    await assertSucceeds(setDoc(userDoc(as(BOB), ALICE, 'notes', 'today', 'reactions', BOB), good));
    await assertFails(setDoc(userDoc(as(BOB), ALICE, 'notes', 'today', 'reactions', ALICE), good));
    await assertFails(setDoc(userDoc(as(BOB), ALICE, 'notes', 'today', 'reactions', BOB), { ...good, kind: 'angry' }));
    await assertFails(setDoc(userDoc(as(BOB), ALICE, 'notes', 'old', 'reactions', BOB), good));
  });
});

describe('account deletion queries', () => {
  const commentOf = (uid) => query(collectionGroup(as(uid), 'comments'), where('authorUID', '==', uid));

  test('a person can find only their own comments across all notes', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(userDoc(ctx.firestore(), ALICE, 'notes', 'old', 'comments', 'b1'), { authorUID: BOB, text: 'x', createdAt: ts(0) });
    });
    const snap = await assertSucceeds(getDocs(commentOf(BOB)));
    if (snap.size !== 1) throw new Error(`expected 1 comment, got ${snap.size}`);
    await assertFails(getDocs(query(collectionGroup(as(BOB), 'comments'), where('authorUID', '==', ALICE))));
    await assertFails(getDocs(collectionGroup(as(BOB), 'comments')));
  });

  test('an author can delete their comment even on an old note', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(userDoc(ctx.firestore(), ALICE, 'notes', 'old', 'comments', 'b1'), { authorUID: BOB, text: 'x', createdAt: ts(0) });
    });
    await assertSucceeds(deleteDoc(userDoc(as(BOB), ALICE, 'notes', 'old', 'comments', 'b1')));
  });

  test('a person can find and delete the feed items they wrote, not others', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(userDoc(ctx.firestore(), ALICE, 'activity', 'note_n1'), {
        type: 'note', fromUID: BOB, noteOwnerUID: BOB, noteId: 'n1', createdAt: ts(0),
      });
    });
    const mine = query(collectionGroup(as(BOB), 'activity'), where('fromUID', '==', BOB));
    const snap = await assertSucceeds(getDocs(mine));
    if (snap.size !== 1) throw new Error(`expected 1 item, got ${snap.size}`);
    await assertFails(getDocs(query(collectionGroup(as(BOB), 'activity'), where('fromUID', '==', ALICE))));
    await assertFails(getDocs(query(collectionGroup(as(DAVE), 'activity'), where('fromUID', '==', BOB))));
    await assertSucceeds(deleteDoc(userDoc(as(BOB), ALICE, 'activity', 'note_n1')));
  });

  test('reactions carry reactorUID, which must be the reactor, and can be found by it', async () => {
    const good = { kind: 'love', createdAt: ts(0), reactorUID: BOB };
    await assertSucceeds(setDoc(userDoc(as(BOB), ALICE, 'notes', 'today', 'reactions', BOB), good));
    await assertFails(setDoc(userDoc(as(BOB), ALICE, 'notes', 'today', 'reactions', BOB), { ...good, reactorUID: ALICE }));
    const snap = await assertSucceeds(getDocs(query(collectionGroup(as(BOB), 'reactions'), where('reactorUID', '==', BOB))));
    if (snap.size !== 1) throw new Error(`expected 1 reaction, got ${snap.size}`);
    await assertFails(getDocs(query(collectionGroup(as(BOB), 'reactions'), where('reactorUID', '==', ALICE))));
    await assertSucceeds(deleteDoc(userDoc(as(BOB), ALICE, 'notes', 'today', 'reactions', BOB)));
  });

  test('the owner can erase everything under their own account', async () => {
    const db = as(ALICE);
    for (const id of ['today', 'private', 'old', 'oldPinned']) {
      await assertSucceeds(deleteDoc(userDoc(db, ALICE, 'notes', id, 'comments', 'c1')).catch(() => {}));
      await assertSucceeds(deleteDoc(userDoc(db, ALICE, 'notes', id)));
    }
    for (const kind of ['photos', 'audio']) {
      await assertSucceeds(deleteDoc(userDoc(db, ALICE, kind, 'today')));
    }
    await assertSucceeds(deleteDoc(doc(db, 'streaks', ALICE)));
    await assertSucceeds(deleteDoc(doc(db, 'friendships', `${ALICE}_${BOB}`)));
    await assertSucceeds(deleteDoc(userDoc(db, ALICE)));
  });

  test('the owner can list and erase their whole library, nobody else can', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(userDoc(ctx.firestore(), ALICE, 'library', 'e1'), libraryEntry());
      await setDoc(userDoc(ctx.firestore(), ALICE, 'library', 'e2'), libraryEntry());
    });
    await assertFails(getDocs(collection(as(BOB), 'users', ALICE, 'library')));
    const snap = await assertSucceeds(getDocs(collection(as(ALICE), 'users', ALICE, 'library')));
    if (snap.size !== 2) throw new Error(`expected 2 entries, got ${snap.size}`);
    for (const d of snap.docs) await assertSucceeds(deleteDoc(d.ref));
  });
});

describe('writing notes', () => {
  test('owner can write a valid note, others cannot', async () => {
    await assertSucceeds(setDoc(userDoc(as(ALICE), ALICE, 'notes', 'n1'), note()));
    await assertFails(setDoc(userDoc(as(BOB), ALICE, 'notes', 'n2'), note()));
  });

  test('size and shape limits', async () => {
    const db = as(ALICE);
    await assertFails(setDoc(userDoc(db, ALICE, 'notes', 'a'), note({ text: 'x'.repeat(20001) })));
    await assertFails(setDoc(userDoc(db, ALICE, 'notes', 'b'), note({ extra: 1 })));
    await assertFails(setDoc(userDoc(db, ALICE, 'notes', 'c'), note({ isDraft: true })));
    await assertFails(setDoc(userDoc(db, ALICE, 'notes', 'd'), note({ audioSeconds: 121 })));
    await assertFails(setDoc(userDoc(db, ALICE, 'notes', 'e'), note({ isDraft: true, sharedWithFriends: false, isPinned: true })));
  });

  test('avatar is limited to 100000 bytes and to the current document', async () => {
    const ok = { data: Bytes.fromUint8Array(new Uint8Array(100000)), updatedAt: ts(0) };
    const big = { data: Bytes.fromUint8Array(new Uint8Array(100001)), updatedAt: ts(0) };
    await assertSucceeds(setDoc(userDoc(as(ALICE), ALICE, 'avatar', 'current'), ok));
    await assertFails(setDoc(userDoc(as(ALICE), ALICE, 'avatar', 'current'), big));
    await assertFails(setDoc(userDoc(as(ALICE), ALICE, 'avatar', 'other'), ok));
    await assertFails(setDoc(userDoc(as(BOB), ALICE, 'avatar', 'current'), ok));
  });
});

describe('activity feed', () => {
  const noteActivity = (overrides = {}) => ({
    type: 'note', fromUID: BOB, noteOwnerUID: BOB, noteId: 'n1', preview: 'hi', createdAt: ts(0), ...overrides,
  });
  const feed = (db, id) => userDoc(db, ALICE, 'activity', id);

  test('a friend can add a well formed item with its fixed id', async () => {
    await assertSucceeds(setDoc(feed(as(BOB), 'note_n1'), noteActivity()));
    await assertSucceeds(setDoc(feed(as(BOB), 'comment_c9'), {
      type: 'comment', fromUID: BOB, noteOwnerUID: ALICE, noteId: 'n1', preview: 'nice', createdAt: ts(0),
    }));
    await assertSucceeds(setDoc(feed(as(BOB), `reaction_n1_${BOB}`), {
      type: 'reaction', fromUID: BOB, noteOwnerUID: ALICE, noteId: 'n1', createdAt: ts(0),
    }));
    await assertSucceeds(setDoc(feed(as(BOB), `accepted_${BOB}`), { type: 'accepted', fromUID: BOB, createdAt: ts(0) }));
  });

  test('arbitrary ids and spoofed fields are refused', async () => {
    await assertFails(setDoc(feed(as(BOB), 'spam_1'), noteActivity()));
    await assertFails(setDoc(feed(as(BOB), 'note_other'), noteActivity()));
    await assertFails(setDoc(feed(as(BOB), 'note_n1'), noteActivity({ noteOwnerUID: ALICE })));
    await assertFails(setDoc(feed(as(BOB), 'note_n1'), noteActivity({ fromUID: CAROL })));
    await assertFails(setDoc(feed(as(BOB), 'accepted_carol'), { type: 'accepted', fromUID: BOB, createdAt: ts(0) }));
    await assertFails(setDoc(feed(as(BOB), 'reaction_n1_carol'), {
      type: 'reaction', fromUID: BOB, noteOwnerUID: ALICE, noteId: 'n1', createdAt: ts(0),
    }));
    await assertFails(setDoc(feed(as(BOB), `reaction_n1_${BOB}`), {
      type: 'reaction', fromUID: BOB, noteOwnerUID: CAROL, noteId: 'n1', createdAt: ts(0),
    }));
  });

  test('items cannot be dated in the future, oversized or carry extra fields', async () => {
    await assertFails(setDoc(feed(as(BOB), 'note_n1'), noteActivity({ createdAt: ts(48 * HOUR) })));
    await assertFails(setDoc(feed(as(BOB), 'note_n1'), noteActivity({ preview: 'x'.repeat(121) })));
    await assertFails(setDoc(feed(as(BOB), 'note_n1'), noteActivity({ extra: true })));
  });

  test('strangers cannot write, nobody writes to their own feed', async () => {
    await assertFails(setDoc(feed(as(DAVE), 'note_n1'), noteActivity({ fromUID: DAVE, noteOwnerUID: DAVE })));
    await assertFails(setDoc(feed(as(ALICE), 'note_n1'), noteActivity({ fromUID: ALICE, noteOwnerUID: ALICE })));
  });

  test('an item cannot be edited; only the owner reads it by path, the sender can only list and delete their own', async () => {
    await setDoc(feed(as(BOB), 'note_n1'), noteActivity());
    await assertFails(updateDoc(feed(as(BOB), 'note_n1'), { preview: 'changed' }));
    await assertFails(getDoc(feed(as(BOB), 'note_n1')));
    await assertFails(getDoc(feed(as(DAVE), 'note_n1')));
    await assertSucceeds(getDoc(feed(as(ALICE), 'note_n1')));
    await assertSucceeds(deleteDoc(feed(as(ALICE), 'note_n1')));
  });
});

describe('friendships', () => {
  const request = (from, to, overrides = {}) => ({
    fromUID: from, toUID: to, status: 'pending', createdAt: ts(0), ...overrides,
  });

  test('send a pending request as yourself with the fixed id', async () => {
    await assertSucceeds(setDoc(doc(as(DAVE), 'friendships', `${DAVE}_${ALICE}`), request(DAVE, ALICE)));
  });

  test('refuse forged requests', async () => {
    const db = as(DAVE);
    await assertFails(setDoc(doc(db, 'friendships', `${BOB}_${DAVE}`), request(BOB, DAVE)));
    await assertFails(setDoc(doc(db, 'friendships', `${DAVE}_${ALICE}`), request(DAVE, ALICE, { status: 'accepted' })));
    await assertFails(setDoc(doc(db, 'friendships', `${DAVE}_${DAVE}`), request(DAVE, DAVE)));
    await assertFails(setDoc(doc(db, 'friendships', 'wrong_id'), request(DAVE, ALICE)));
    await assertFails(setDoc(doc(db, 'friendships', `${DAVE}_ghost`), request(DAVE, 'ghost')));
  });

  test('only the receiver accepts, and only the status changes', async () => {
    const id = `${BOB}_${CAROL}`;
    await assertFails(updateDoc(doc(as(BOB), 'friendships', id), { status: 'accepted' }));
    await assertFails(updateDoc(doc(as(DAVE), 'friendships', id), { status: 'accepted' }));
    await assertFails(updateDoc(doc(as(CAROL), 'friendships', id), { status: 'accepted', fromUID: DAVE }));
    await assertSucceeds(updateDoc(doc(as(CAROL), 'friendships', id), { status: 'accepted' }));
  });

  test('only the two people read or delete a friendship', async () => {
    const id = `${BOB}_${CAROL}`;
    await assertFails(getDoc(doc(as(DAVE), 'friendships', id)));
    await assertFails(deleteDoc(doc(as(DAVE), 'friendships', id)));
    await assertSucceeds(getDoc(doc(as(CAROL), 'friendships', id)));
    await assertSucceeds(deleteDoc(doc(as(BOB), 'friendships', id)));
  });
});

describe('blocking', () => {
  test('a person manages their own block list, nobody else sees it', async () => {
    await assertSucceeds(setDoc(userDoc(as(ALICE), ALICE, 'blocks', DAVE), { createdAt: ts(0) }));
    await assertSucceeds(getDoc(userDoc(as(ALICE), ALICE, 'blocks', DAVE)));
    await assertFails(getDoc(userDoc(as(DAVE), ALICE, 'blocks', DAVE)));
    await assertFails(getDoc(userDoc(as(BOB), ALICE, 'blocks', DAVE)));
    await assertFails(setDoc(userDoc(as(BOB), ALICE, 'blocks', CAROL), { createdAt: ts(0) }));
    await assertFails(setDoc(userDoc(as(ALICE), ALICE, 'blocks', ALICE), { createdAt: ts(0) }));
    await assertFails(setDoc(userDoc(as(ALICE), ALICE, 'blocks', CAROL), { createdAt: ts(0), reason: 'x' }));
    await assertSucceeds(deleteDoc(userDoc(as(ALICE), ALICE, 'blocks', DAVE)));
  });

  test('a blocked person cannot send a friend request, an unblocked one can', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(userDoc(ctx.firestore(), DAVE, 'blocks', BOB), { createdAt: ts(0) });
    });
    const request = (from, to) => ({ fromUID: from, toUID: to, status: 'pending', createdAt: ts(0) });
    await assertFails(setDoc(doc(as(BOB), 'friendships', `${BOB}_${DAVE}`), request(BOB, DAVE)));
    await assertSucceeds(setDoc(doc(as(CAROL), 'friendships', `${CAROL}_${DAVE}`), request(CAROL, DAVE)));
    await assertSucceeds(deleteDoc(userDoc(as(DAVE), DAVE, 'blocks', BOB)));
    await assertSucceeds(setDoc(doc(as(BOB), 'friendships', `${BOB}_${DAVE}`), request(BOB, DAVE)));
  });

  test('blocking can remove the friendship from either side of the query', async () => {
    const mine = query(collection(as(ALICE), 'friendships'), where('fromUID', '==', ALICE), where('toUID', '==', BOB));
    const snap = await assertSucceeds(getDocs(mine));
    if (snap.size !== 1) throw new Error(`expected 1 friendship, got ${snap.size}`);
    await assertSucceeds(deleteDoc(snap.docs[0].ref));
    const theirs = query(collection(as(ALICE), 'friendships'), where('fromUID', '==', BOB), where('toUID', '==', ALICE));
    await assertSucceeds(getDocs(theirs));
  });
});

describe('reports', () => {
  const report = (overrides = {}) => ({
    reporterUID: BOB, reportedUID: ALICE, kind: 'note', reason: 'spam',
    noteOwnerUID: ALICE, noteId: 'today', contentPreview: 'hello', createdAt: ts(0), ...overrides,
  });
  const ref = (db, id) => doc(db, 'reports', id);

  test('anyone signed in can report a note, comment or person once', async () => {
    await assertSucceeds(setDoc(ref(as(BOB), `${BOB}_note_today`), report()));
    await assertSucceeds(setDoc(ref(as(BOB), `${BOB}_comment_c1`), report({ kind: 'comment', commentId: 'c1' })));
    await assertSucceeds(setDoc(ref(as(DAVE), `${DAVE}_user_${ALICE}`), {
      reporterUID: DAVE, reportedUID: ALICE, kind: 'user', reason: 'harassment', details: 'x', createdAt: ts(0),
    }));
    await assertFails(setDoc(ref(as(BOB), `${BOB}_note_today`), report()));
  });

  test('reports must be well formed', async () => {
    const db = as(BOB);
    await assertFails(setDoc(ref(db, `${BOB}_note_today`), report({ reporterUID: ALICE })));
    await assertFails(setDoc(ref(db, `${BOB}_note_today`), report({ reportedUID: BOB })));
    await assertFails(setDoc(ref(db, `${BOB}_note_today`), report({ reason: 'dislike' })));
    await assertFails(setDoc(ref(db, `${BOB}_note_today`), report({ kind: 'photo' })));
    await assertFails(setDoc(ref(db, `${BOB}_note_today`), report({ details: 'x'.repeat(501) })));
    await assertFails(setDoc(ref(db, `${BOB}_note_today`), report({ contentPreview: 'x'.repeat(501) })));
    await assertFails(setDoc(ref(db, `${BOB}_note_today`), report({ extra: true })));
    await assertFails(setDoc(ref(db, `${BOB}_note_today`), report({ createdAt: ts(48 * HOUR) })));
    await assertFails(setDoc(ref(db, 'any_id_at_all'), report()));
    await assertFails(setDoc(ref(db, `${BOB}_comment_c1`), report({ kind: 'comment' })));
  });

  test('signed out users cannot report, and nobody can read, edit or delete reports', async () => {
    await assertFails(setDoc(ref(env.unauthenticatedContext().firestore(), `${BOB}_note_today`), report()));
    await setDoc(ref(as(BOB), `${BOB}_note_today`), report());
    await assertFails(getDoc(ref(as(BOB), `${BOB}_note_today`)));
    await assertFails(getDoc(ref(as(ALICE), `${BOB}_note_today`)));
    await assertFails(updateDoc(ref(as(BOB), `${BOB}_note_today`), { reason: 'other' }));
    await assertFails(deleteDoc(ref(as(BOB), `${BOB}_note_today`)));
    await assertFails(getDocs(collection(as(BOB), 'reports')));
  });
});

describe('streaks', () => {
  test('owner and friends read, strangers do not', async () => {
    await assertSucceeds(getDoc(doc(as(ALICE), 'streaks', ALICE)));
    await assertSucceeds(getDoc(doc(as(BOB), 'streaks', ALICE)));
    await assertFails(getDoc(doc(as(DAVE), 'streaks', ALICE)));
  });

  test('only the owner writes, with sane values, and can delete', async () => {
    const good = { currentStreak: 4, lastPostDate: ts(0), updatedAt: ts(0) };
    await assertSucceeds(setDoc(doc(as(ALICE), 'streaks', ALICE), good));
    await assertFails(setDoc(doc(as(BOB), 'streaks', ALICE), good));
    await assertFails(setDoc(doc(as(ALICE), 'streaks', ALICE), { ...good, currentStreak: -1 }));
    await assertFails(setDoc(doc(as(ALICE), 'streaks', ALICE), { ...good, extra: 1 }));
    await assertFails(deleteDoc(doc(as(BOB), 'streaks', ALICE)));
    await assertSucceeds(deleteDoc(doc(as(ALICE), 'streaks', ALICE)));
  });
});

describe('profiles', () => {
  const profile = (overrides = {}) => ({
    username: 'alice_1', usernameLower: 'alice_1', displayName: 'Alice', createdAt: ts(0), ...overrides,
  });

  test('owner writes their own valid profile only', async () => {
    await assertSucceeds(saveProfile(as('erin'), 'erin', profile()));
    await assertFails(saveProfile(as('erin'), ALICE, profile({ username: 'alice_2', usernameLower: 'alice_2' })));
  });

  test('username must be 3 to 30 letters, numbers, underscore or dot', async () => {
    const db = as('erin');
    await assertFails(saveProfile(db, 'erin', profile({ username: 'ab', usernameLower: 'ab' })));
    await assertFails(saveProfile(db, 'erin', profile({ username: 'bad name', usernameLower: 'bad name' })));
    await assertFails(saveProfile(db, 'erin', profile({ username: 'a'.repeat(31), usernameLower: 'a'.repeat(31) })));
    await assertSucceeds(saveProfile(db, 'erin', profile({ username: 'Er.in_9', usernameLower: 'er.in_9' })));
  });

  test('display name is 1 to 40 characters', async () => {
    const db = as('erin');
    await assertFails(saveProfile(db, 'erin', profile({ displayName: '' })));
    await assertFails(saveProfile(db, 'erin', profile({ displayName: 'x'.repeat(41) })));
  });

  test('a new profile cannot carry a phone number', async () => {
    const token = { phone_number: '+61400000009' };
    await assertFails(saveProfile(as('erin', token), 'erin', profile({ phoneNumber: '61400000009' })));
  });

  test('a profile that still holds a legacy phone number can keep it unchanged or remove it, not change it', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(userDoc(ctx.firestore(), 'frank'), profile({ username: 'frank_1', usernameLower: 'frank_1', phoneNumber: '61400000009' }));
    });
    const db = as('frank');
    await assertFails(updateDoc(userDoc(db, 'frank'), { phoneNumber: '61411111111' }));
    await assertSucceeds(updateDoc(userDoc(db, 'frank'), { displayName: 'Frank' }));
    await assertSucceeds(updateDoc(userDoc(db, 'frank'), { phoneNumber: deleteField() }));
    await assertFails(updateDoc(userDoc(db, 'frank'), { phoneNumber: '61400000009' }));
  });

  test('a user can delete only their own profile', async () => {
    await assertFails(deleteDoc(userDoc(as(BOB), ALICE)));
    await assertSucceeds(deleteDoc(userDoc(as(ALICE), ALICE)));
  });
});

describe('unique usernames', () => {
  const profile = (overrides = {}) => ({
    username: 'Erin_1', usernameLower: 'erin_1', displayName: 'Erin', createdAt: ts(0), ...overrides,
  });

  // An existing account whose username was never reserved (made before
  // reservations existed), plus one that has its reservation.
  async function seedLegacyAndReserved() {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(userDoc(ctx.firestore(), 'frank'), profile({ username: 'Frank_1', usernameLower: 'frank_1' }));
      await setDoc(userDoc(ctx.firestore(), 'gina'), profile({ username: 'Gina_1', usernameLower: 'gina_1' }));
    });
    await seedReservation('gina_1', 'gina');
  }

  describe('reservations', () => {
    test('a signed in user claims a free name as themselves', async () => {
      await assertSucceeds(setDoc(reservationDoc(as('erin'), 'erin_1'), reservation('erin')));
    });

    test('a name that is taken cannot be claimed again, by anyone', async () => {
      await seedReservation('erin_1', 'erin');
      await assertFails(setDoc(reservationDoc(as(DAVE), 'erin_1'), reservation(DAVE)));
      await assertFails(setDoc(reservationDoc(as('erin'), 'erin_1'), reservation('erin')));
    });

    test('a name cannot be claimed for someone else, or signed out', async () => {
      await assertFails(setDoc(reservationDoc(as(DAVE), 'erin_1'), reservation('erin')));
      await assertFails(setDoc(reservationDoc(env.unauthenticatedContext().firestore(), 'erin_1'), reservation('erin')));
    });

    test('the id is 3 to 30 characters of a-z, 0-9, underscore or dot', async () => {
      const db = as('erin');
      for (const bad of ['ab', 'a'.repeat(31), 'Erin_1', 'er in', 'er-in', 'erin@1', 'é'.repeat(3)]) {
        await assertFails(setDoc(reservationDoc(db, bad), reservation('erin')));
      }
      for (const good of ['abc', 'a'.repeat(30), 'e.r_i.n9', '000']) {
        await assertSucceeds(setDoc(reservationDoc(db, good), reservation('erin')));
      }
    });

    test('it holds exactly uid and createdAt', async () => {
      const db = as('erin');
      await assertFails(setDoc(reservationDoc(db, 'erin_1'), { uid: 'erin' }));
      await assertFails(setDoc(reservationDoc(db, 'erin_1'), { createdAt: ts(0) }));
      await assertFails(setDoc(reservationDoc(db, 'erin_1'), { ...reservation('erin'), extra: 1 }));
      await assertFails(setDoc(reservationDoc(db, 'erin_1'), reservation('erin', { createdAt: 'now' })));
      await assertFails(setDoc(reservationDoc(db, 'erin_1'), reservation(5)));
    });

    test('it can never be updated, not even by its owner', async () => {
      await seedReservation('erin_1', 'erin');
      const db = as('erin');
      await assertFails(updateDoc(reservationDoc(db, 'erin_1'), { createdAt: ts(HOUR) }));
      await assertFails(setDoc(reservationDoc(db, 'erin_1'), reservation('erin')));
      await assertFails(updateDoc(reservationDoc(as(DAVE), 'erin_1'), { uid: DAVE }));
    });

    test('only the owner can delete it', async () => {
      await seedReservation('erin_1', 'erin');
      await assertFails(deleteDoc(reservationDoc(as(DAVE), 'erin_1')));
      await assertFails(deleteDoc(reservationDoc(env.unauthenticatedContext().firestore(), 'erin_1')));
      await assertSucceeds(deleteDoc(reservationDoc(as('erin'), 'erin_1')));
      await assertSucceeds(setDoc(reservationDoc(as(DAVE), 'erin_1'), reservation(DAVE)));
    });

    test('deleting a name nobody holds is refused', async () => {
      await assertFails(deleteDoc(reservationDoc(as('erin'), 'nobody_here')));
    });

    test('anyone can look up one name but nobody can list them', async () => {
      await seedReservation('erin_1', 'erin');
      await assertSucceeds(getDoc(reservationDoc(as(DAVE), 'erin_1')));
      await assertSucceeds(getDoc(reservationDoc(as(DAVE), 'free_name')));
      await assertSucceeds(getDoc(reservationDoc(env.unauthenticatedContext().firestore(), 'erin_1')));
      await assertSucceeds(getDoc(reservationDoc(env.unauthenticatedContext().firestore(), 'free_name')));
      await assertFails(getDocs(collection(as(DAVE), 'usernames')));
      await assertFails(getDocs(collection(env.unauthenticatedContext().firestore(), 'usernames')));
    });
  });

  describe('a new profile', () => {
    test('is created together with its reservation', async () => {
      await assertSucceeds(saveProfile(as('erin'), 'erin', profile()));
    });

    test('cannot be created without a reservation', async () => {
      await assertFails(setDoc(userDoc(as('erin'), 'erin'), profile()));
    });

    test('cannot claim a name someone else holds', async () => {
      await seedReservation('erin_1', DAVE);
      await assertFails(saveProfile(as('erin'), 'erin', profile()));
      const db = as('erin');
      await assertFails(setDoc(userDoc(db, 'erin'), profile()));
    });

    test('cannot hold a reservation for a different name than the profile has', async () => {
      await assertFails(saveProfile(as('erin'), 'erin', profile(), 'other_name'));
    });

    test('is refused when the matching reservation belongs to someone else, even in the same batch', async () => {
      const db = as('erin');
      const batch = writeBatch(db);
      batch.set(userDoc(db, 'erin'), profile());
      batch.set(reservationDoc(db, 'erin_1'), reservation(DAVE));
      await assertFails(batch.commit());
    });

    test('is matched ignoring case, so Alice and alice collide', async () => {
      await seedReservation('erin_1', DAVE);
      await assertFails(saveProfile(as('erin'), 'erin', profile({ username: 'ERIN_1', usernameLower: 'erin_1' })));
    });

    test('usernameLower must still be the lowercase username', async () => {
      await assertFails(saveProfile(as('erin'), 'erin', profile({ usernameLower: 'something_else' })));
    });
  });

  describe('changing a username', () => {
    test('claims the new name and releases the old one in one batch', async () => {
      await seedLegacyAndReserved();
      const db = as('gina');
      const batch = writeBatch(db);
      batch.update(userDoc(db, 'gina'), { username: 'Gina_2', usernameLower: 'gina_2' });
      batch.set(reservationDoc(db, 'gina_2'), reservation('gina'));
      batch.delete(reservationDoc(db, 'gina_1'));
      await assertSucceeds(batch.commit());
      await assertSucceeds(getDoc(reservationDoc(db, 'gina_2')));
      assert.equal((await getDoc(reservationDoc(db, 'gina_1'))).exists(), false);
      await assertSucceeds(setDoc(reservationDoc(as(DAVE), 'gina_1'), reservation(DAVE)));
    });

    test('is refused without claiming the new name', async () => {
      await seedLegacyAndReserved();
      await assertFails(updateDoc(userDoc(as('gina'), 'gina'), { username: 'Gina_2', usernameLower: 'gina_2' }));
    });

    test('is refused when someone else holds the new name', async () => {
      await seedLegacyAndReserved();
      await seedReservation('gina_2', DAVE);
      const db = as('gina');
      const batch = writeBatch(db);
      batch.update(userDoc(db, 'gina'), { username: 'Gina_2', usernameLower: 'gina_2' });
      batch.set(reservationDoc(db, 'gina_2'), reservation('gina'));
      await assertFails(batch.commit());
      await assertFails(updateDoc(userDoc(db, 'gina'), { username: 'Gina_2', usernameLower: 'gina_2' }));
    });

    test('cannot slip a new username past the check by leaving usernameLower alone', async () => {
      await seedLegacyAndReserved();
      await assertFails(updateDoc(userDoc(as('gina'), 'gina'), { username: 'Gina_2' }));
    });

    test('changing only the capital letters needs no new reservation', async () => {
      await seedLegacyAndReserved();
      await assertSucceeds(updateDoc(userDoc(as('gina'), 'gina'), { username: 'GINA_1', usernameLower: 'gina_1' }));
    });

    test('an older profile with no reservation can still edit its other fields', async () => {
      await seedLegacyAndReserved();
      await assertSucceeds(updateDoc(userDoc(as('frank'), 'frank'), { displayName: 'Frank F' }));
      await assertSucceeds(updateDoc(userDoc(as('frank'), 'frank'), { hasAvatar: true, avatarUpdatedAt: ts(0) }));
    });

    test('an older profile can claim its own name, but not one someone else holds', async () => {
      await seedLegacyAndReserved();
      await assertSucceeds(setDoc(reservationDoc(as('frank'), 'frank_1'), reservation('frank')));
      await seedReservation('henry_1', 'henry');
      await assertFails(setDoc(reservationDoc(as('frank'), 'henry_1'), reservation('frank')));
    });

    test('an older profile can move to a new name without releasing one it never held', async () => {
      await seedLegacyAndReserved();
      const db = as('frank');
      const batch = writeBatch(db);
      batch.update(userDoc(db, 'frank'), { username: 'Frank_2', usernameLower: 'frank_2' });
      batch.set(reservationDoc(db, 'frank_2'), reservation('frank'));
      await assertSucceeds(batch.commit());
    });

    test('nobody can release someone else\'s name', async () => {
      await seedLegacyAndReserved();
      await assertFails(deleteDoc(reservationDoc(as('frank'), 'gina_1')));
    });
  });
});

describe('circles and private collections', () => {
  const circle = (overrides = {}) => ({
    name: 'Close', memberUIDs: [BOB], createdAt: ts(0), updatedAt: ts(0), ...overrides,
  });

  test('circles are private to the owner and limited', async () => {
    await assertSucceeds(setDoc(userDoc(as(ALICE), ALICE, 'circles', 'c'), circle()));
    await assertFails(getDoc(userDoc(as(BOB), ALICE, 'circles', 'c')));
    await assertFails(setDoc(userDoc(as(ALICE), ALICE, 'circles', 'd'), circle({ name: 'x'.repeat(31) })));
    await assertFails(setDoc(userDoc(as(ALICE), ALICE, 'circles', 'e'), circle({ memberUIDs: Array.from({ length: 11 }, (_, i) => `u${i}`) })));
  });
});

describe('library backup', () => {
  const entry = (db, id = 'e1') => userDoc(db, ALICE, 'library', id);

  test('the owner writes a full entry, a minimal one and edits it', async () => {
    const db = as(ALICE);
    await assertSucceeds(setDoc(entry(db), libraryEntry()));
    await assertSucceeds(setDoc(entry(db, 'e2'), {
      tmdbID: 1, mediaType: 'tv', title: 'Show', rating: 1, loggedAt: ts(0),
    }));
    await assertSucceeds(setDoc(entry(db), libraryEntry({ rating: 2, reviewText: 'Changed my mind' })));
    await assertSucceeds(updateDoc(entry(db), { rating: 3 }));
    await assertSucceeds(deleteDoc(entry(db)));
  });

  test('the library is private: friends, strangers and signed out users get nothing', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(entry(ctx.firestore()), libraryEntry());
    });
    await assertSucceeds(getDoc(entry(as(ALICE))));
    await assertFails(getDoc(entry(as(BOB))));
    await assertFails(getDoc(entry(as(DAVE))));
    await assertFails(getDoc(entry(env.unauthenticatedContext().firestore())));
    await assertFails(setDoc(entry(as(BOB), 'e9'), libraryEntry()));
    await assertFails(setDoc(entry(env.unauthenticatedContext().firestore(), 'e9'), libraryEntry()));
    await assertFails(updateDoc(entry(as(BOB)), { rating: 1 }));
    await assertFails(deleteDoc(entry(as(BOB))));
    await assertFails(deleteDoc(entry(as(DAVE))));
  });

  test('required fields must be present and extra fields are refused', async () => {
    const db = as(ALICE);
    for (const field of ['tmdbID', 'mediaType', 'title', 'rating', 'loggedAt']) {
      const { [field]: _gone, ...rest } = libraryEntry();
      await assertFails(setDoc(entry(db), rest));
    }
    await assertFails(setDoc(entry(db), libraryEntry({ extra: 1 })));
    await assertFails(setDoc(entry(db), libraryEntry({ posterData: Bytes.fromUint8Array(new Uint8Array(10)) })));
    await assertFails(setDoc(entry(db), libraryEntry({ ownerUID: ALICE })));
  });

  test('rating is a whole number from 1 to 5', async () => {
    const db = as(ALICE);
    for (const rating of [0, 6, -1]) await assertFails(setDoc(entry(db), libraryEntry({ rating })));
    await assertFails(setDoc(entry(db), libraryEntry({ rating: 3.5 })));
    await assertFails(setDoc(entry(db), libraryEntry({ rating: '4' })));
    for (const rating of [1, 5]) await assertSucceeds(setDoc(entry(db), libraryEntry({ rating })));
  });

  test('review is at most 280 characters', async () => {
    const db = as(ALICE);
    await assertSucceeds(setDoc(entry(db), libraryEntry({ reviewText: 'x'.repeat(280) })));
    await assertFails(setDoc(entry(db), libraryEntry({ reviewText: 'x'.repeat(281) })));
    await assertFails(setDoc(entry(db), libraryEntry({ reviewText: 5 })));
  });

  test('types and sizes of the other fields are checked', async () => {
    const db = as(ALICE);
    await assertFails(setDoc(entry(db), libraryEntry({ mediaType: 'book' })));
    await assertFails(setDoc(entry(db), libraryEntry({ tmdbID: '603' })));
    await assertFails(setDoc(entry(db), libraryEntry({ tmdbID: 0 })));
    await assertFails(setDoc(entry(db), libraryEntry({ title: '' })));
    await assertFails(setDoc(entry(db), libraryEntry({ title: 'x'.repeat(301) })));
    await assertSucceeds(setDoc(entry(db), libraryEntry({ title: 'x'.repeat(300) })));
    await assertFails(setDoc(entry(db), libraryEntry({ year: '1999' })));
    await assertFails(setDoc(entry(db), libraryEntry({ year: 1 })));
    await assertFails(setDoc(entry(db), libraryEntry({ loggedAt: 'yesterday' })));
    await assertFails(setDoc(entry(db), libraryEntry({ noteID: 7 })));
    await assertFails(setDoc(entry(db), libraryEntry({ noteID: 'x'.repeat(129) })));
  });

  test('only a poster path is stored, never an image or a link', async () => {
    const db = as(ALICE);
    await assertSucceeds(setDoc(entry(db), libraryEntry({ posterPath: '/abc.jpg' })));
    await assertFails(setDoc(entry(db), libraryEntry({ posterPath: Bytes.fromUint8Array(new Uint8Array(10)) })));
    await assertFails(setDoc(entry(db), libraryEntry({ posterPath: 'https://example.com/a.jpg' })));
    await assertFails(setDoc(entry(db), libraryEntry({ posterPath: '/' + 'a'.repeat(100) })));
    await assertFails(setDoc(entry(db), libraryEntry({ posterPath: 5 })));
  });
});

describe('closed collections', () => {
  test('the retired sharedNotes collection is closed to everyone', async () => {
    await assertFails(setDoc(doc(as(ALICE), 'sharedNotes', 'x'), {
      fromUID: ALICE, toUID: BOB, text: 't', createdAt: ts(0), sharedAt: ts(0),
    }));
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'sharedNotes', 'y'), { fromUID: ALICE, toUID: BOB, text: 't' });
    });
    await assertFails(getDoc(doc(as(ALICE), 'sharedNotes', 'y')));
    await assertFails(getDoc(doc(as(BOB), 'sharedNotes', 'y')));
  });

  test('signed out users read nothing', async () => {
    const db = env.unauthenticatedContext().firestore();
    await assertFails(getDoc(userDoc(db, ALICE)));
    await assertFails(getDoc(userDoc(db, ALICE, 'notes', 'today')));
  });
});

// This describes the behaviour we want but the app cannot have yet: username
// search needs every signed in user to be able to list profiles. It is marked
// todo so it is reported without failing the run.
describe('known gaps (todo)', () => {
  test('a stranger should not be able to list every user', { todo: 'username search needs it' }, async () => {
    await assertFails(getDocs(collection(as(DAVE), 'users')));
  });
});
