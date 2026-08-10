import fs from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  deleteDoc,
  doc,
  getDoc,
  setDoc,
  updateDoc,
} from 'firebase/firestore';

const projectId = 'demo-asta-matrix-rules';
let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: fs.readFileSync('firestore.rules', 'utf8'),
    },
  });
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();

    await setDoc(doc(db, 'players', 'legacy-1'), {
      name: 'Legacy Player',
    });

    await setDoc(doc(db, 'auction_sessions', 'session-1'), {
      owner_uid: 'alice',
      member_uids: ['alice', 'bob'],
      name: 'Asta Matrix',
      status: 'live',
    });

    await setDoc(doc(db, 'auction_sessions', 'session-1', 'players', 'p1'), {
      name: 'Player One',
    });

    await setDoc(doc(db, 'auction_sessions', 'session-1', 'live', 'current'), {
      phase: 'idle',
      revision: 0,
      controller_instance_id: 'controller-a',
    });
  });
});

after(async () => {
  await env.cleanup();
});

test('legacy catalog is signed-in read-only', async () => {
  const anonymous = env.unauthenticatedContext().firestore();
  const alice = env.authenticatedContext('alice').firestore();

  await assertFails(getDoc(doc(anonymous, 'players', 'legacy-1')));
  await assertSucceeds(getDoc(doc(alice, 'players', 'legacy-1')));
  await assertFails(
    setDoc(doc(alice, 'players', 'new-player'), { name: 'No write' }),
  );
});

test('session members can read while outsiders cannot', async () => {
  const bob = env.authenticatedContext('bob').firestore();
  const charlie = env.authenticatedContext('charlie').firestore();

  await assertSucceeds(getDoc(doc(bob, 'auction_sessions', 'session-1')));
  await assertSucceeds(
    getDoc(doc(bob, 'auction_sessions', 'session-1', 'players', 'p1')),
  );
  await assertSucceeds(
    getDoc(doc(bob, 'auction_sessions', 'session-1', 'live', 'current')),
  );

  await assertFails(getDoc(doc(charlie, 'auction_sessions', 'session-1')));
  await assertFails(
    getDoc(doc(charlie, 'auction_sessions', 'session-1', 'live', 'current')),
  );
});

test('only owner can mutate session scoped data', async () => {
  const alice = env.authenticatedContext('alice').firestore();
  const bob = env.authenticatedContext('bob').firestore();

  await assertSucceeds(
    setDoc(doc(alice, 'auction_sessions', 'session-1', 'players', 'p2'), {
      name: 'Player Two',
    }),
  );
  await assertFails(
    setDoc(doc(bob, 'auction_sessions', 'session-1', 'players', 'p3'), {
      name: 'Player Three',
    }),
  );

  await assertSucceeds(
    updateDoc(doc(alice, 'auction_sessions', 'session-1', 'live', 'current'), {
      revision: 1,
      controller_instance_id: 'controller-b',
    }),
  );
  await assertFails(
    updateDoc(doc(bob, 'auction_sessions', 'session-1', 'live', 'current'), {
      revision: 2,
    }),
  );
});

test('events are owner-created and immutable', async () => {
  const alice = env.authenticatedContext('alice').firestore();
  const bob = env.authenticatedContext('bob').firestore();
  const eventRef = doc(
    alice,
    'auction_sessions',
    'session-1',
    'events',
    'event-1',
  );

  await assertSucceeds(
    setDoc(eventRef, {
      id: 'event-1',
      type: 'playerNominated',
      created_by_uid: 'alice',
    }),
  );

  await assertFails(updateDoc(eventRef, { type: 'bidChanged' }));
  await assertFails(deleteDoc(eventRef));

  await assertFails(
    setDoc(
      doc(bob, 'auction_sessions', 'session-1', 'events', 'event-bob'),
      {
        id: 'event-bob',
        type: 'bidRaised',
        created_by_uid: 'bob',
      },
    ),
  );
});

test('owner cannot transfer session ownership by update', async () => {
  const alice = env.authenticatedContext('alice').firestore();
  const sessionRef = doc(alice, 'auction_sessions', 'session-1');

  await assertFails(
    updateDoc(sessionRef, {
      owner_uid: 'bob',
      member_uids: ['alice', 'bob'],
    }),
  );
});
