import fs from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  orderBy,
  query,
  setDoc,
  updateDoc,
  where,
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

    await setDoc(doc(db, 'auction_sessions', 'session-2'), {
      owner_uid: 'alice',
      member_uids: ['alice'],
      name: 'Seconda asta',
      status: 'live',
      my_team_id: 'team-alice',
      initial_teams: [
        { id: 'team-alice', name: 'Alice FC', credits_remaining: 100 },
        { id: 'team-bob', name: 'Bob FC', credits_remaining: 100 },
      ],
    });

    await setDoc(
      doc(db, 'auction_sessions', 'session-2', 'private', 'sharing'),
      {
        owner_uid: 'alice',
        session_id: 'session-2',
        enabled: true,
        token: 'abcdefghijklmnopqrstuvwxyz123456',
      },
    );

    await setDoc(doc(db, 'auction_sessions', 'session-charlie'), {
      owner_uid: 'charlie',
      member_uids: ['charlie'],
      name: 'Asta Charlie',
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

    await setDoc(doc(db, 'auction_sessions', 'session-2', 'live', 'current'), {
      phase: 'idle',
      revision: 0,
      controller_instance_id: 'controller-a',
    });
  });
});

after(async () => {
  await env.cleanup();
});

test('global player catalog is inaccessible to clients', async () => {
  const anonymous = env.unauthenticatedContext().firestore();
  const alice = env.authenticatedContext('alice').firestore();

  await assertFails(getDoc(doc(anonymous, 'players', 'legacy-1')));
  await assertFails(getDoc(doc(alice, 'players', 'legacy-1')));
  await assertFails(
    setDoc(doc(alice, 'players', 'new-player'), { name: 'No write' }),
  );
});

test('owner query by owner_uid and name ordering is allowed', async () => {
  const alice = env.authenticatedContext('alice').firestore();
  const ownedSessions = query(
    collection(alice, 'auction_sessions'),
    where('owner_uid', '==', 'alice'),
    orderBy('name'),
  );

  const snapshot = await assertSucceeds(getDocs(ownedSessions));
  if (snapshot.size !== 2) {
    throw new Error(`Expected 2 owned sessions, got ${snapshot.size}.`);
  }
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

test('invite secret remains owner-only even for session members', async () => {
  const alice = env.authenticatedContext('alice').firestore();
  const bob = env.authenticatedContext('bob').firestore();
  const sharingPath = [
    'auction_sessions',
    'session-2',
    'private',
    'sharing',
  ];

  await assertSucceeds(getDoc(doc(alice, ...sharingPath)));
  await assertFails(getDoc(doc(bob, ...sharingPath)));
  await assertFails(
    setDoc(doc(bob, ...sharingPath), {
      enabled: true,
      token: 'malicious-token-that-is-long-enough',
    }),
  );
});

test('join request is private to requester and owner', async () => {
  const bob = env.authenticatedContext('bob').firestore();
  const alice = env.authenticatedContext('alice').firestore();
  const charlie = env.authenticatedContext('charlie').firestore();
  const requestId = 'session-2--bob';
  const requestData = {
    session_id: 'session-2',
    owner_uid: 'alice',
    requester_uid: 'bob',
    invite_token: 'abcdefghijklmnopqrstuvwxyz123456',
    status: 'pending',
  };

  await assertSucceeds(
    setDoc(doc(bob, 'auction_join_requests', requestId), requestData),
  );
  await assertSucceeds(
    getDoc(doc(bob, 'auction_join_requests', requestId)),
  );
  await assertSucceeds(
    getDoc(doc(alice, 'auction_join_requests', requestId)),
  );
  await assertFails(
    getDoc(doc(charlie, 'auction_join_requests', requestId)),
  );
  await assertFails(
    updateDoc(doc(bob, 'auction_join_requests', requestId), {
      status: 'approved',
    }),
  );
});

test('join request cannot impersonate another requester', async () => {
  const bob = env.authenticatedContext('bob').firestore();

  await assertFails(
    setDoc(doc(bob, 'auction_join_requests', 'session-2--charlie'), {
      session_id: 'session-2',
      owner_uid: 'alice',
      requester_uid: 'charlie',
      invite_token: 'abcdefghijklmnopqrstuvwxyz123456',
      status: 'pending',
    }),
  );
});

test('only owner can approve membership and approved member becomes viewer', async () => {
  const bob = env.authenticatedContext('bob').firestore();
  const alice = env.authenticatedContext('alice').firestore();
  const requestId = 'session-2--bob';

  await assertFails(getDoc(doc(bob, 'auction_sessions', 'session-2')));

  await assertSucceeds(
    setDoc(doc(bob, 'auction_join_requests', requestId), {
      session_id: 'session-2',
      owner_uid: 'alice',
      requester_uid: 'bob',
      invite_token: 'abcdefghijklmnopqrstuvwxyz123456',
      status: 'pending',
    }),
  );

  await assertFails(
    updateDoc(doc(bob, 'auction_sessions', 'session-2'), {
      member_uids: ['alice', 'bob'],
    }),
  );

  await assertSucceeds(
    updateDoc(doc(alice, 'auction_sessions', 'session-2'), {
      member_uids: ['alice', 'bob'],
      member_team_ids: {
        alice: 'team-alice',
        bob: 'team-bob',
      },
    }),
  );
  await assertSucceeds(
    updateDoc(doc(alice, 'auction_join_requests', requestId), {
      status: 'approved',
      assigned_team_id: 'team-bob',
    }),
  );

  await assertSucceeds(getDoc(doc(bob, 'auction_sessions', 'session-2')));
  await assertSucceeds(
    getDoc(doc(bob, 'auction_sessions', 'session-2', 'live', 'current')),
  );
  await assertFails(
    updateDoc(doc(bob, 'auction_sessions', 'session-2', 'live', 'current'), {
      revision: 99,
    }),
  );
  await assertFails(
    getDoc(
      doc(bob, 'auction_sessions', 'session-2', 'private', 'sharing'),
    ),
  );
});
