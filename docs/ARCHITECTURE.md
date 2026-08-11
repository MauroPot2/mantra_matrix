# Asta Matrix architecture

## Boundaries

Asta Matrix keeps five concerns separate:

1. **Player data source** — explicit user import today, first-party Matrix data source later.
2. **Auction domain** — deterministic commands, events, reducer and advisor.
3. **Persistence** — isolated Firestore session snapshots and immutable events.
4. **Realtime coordination** — one owner/controller instance, many read-only viewers, shared server-clock countdown.
5. **Sharing** — private invite tokens, join requests and owner-approved membership.

The runtime has no dependency on a global third-party player catalog. Player data belongs to the auction that imported it.

## Session lifecycle

```text
import -> setup -> session snapshot -> live auction -> completed
```

Creating a session writes metadata first, initializes `live/current`, persists the player snapshot in bounded batches, and finally marks the snapshot ready. Event streaming begins only after the initial cloud save is confirmed.

Closing an auction is cloud-authoritative: the local live session is cleared only after Firestore confirms the status update. A failed completion write leaves the live session open so it can be retried safely.

## Event sourcing

Auction mutations are append-only events. The reducer rebuilds the effective state from the initial session snapshot plus the event sequence. Undo is represented by a compensating `eventReverted` event rather than destructive deletion.

Realtime events receive a monotonically increasing `server_revision`. Optimistic local events are tracked explicitly as pending. The client renders confirmed server events in revision order and appends still-pending local events in their original production order. A partial Firestore ACK therefore cannot reorder a rapid sequence of bids.

## Realtime clock

The cloud stores:

- server `started_at`;
- accumulated extension seconds;
- current bid;
- active player;
- revision;
- controlling app instance.

Clients render the countdown locally. No per-second Firestore writes are required. Each device calibrates its local clock against the latest Firestore server timestamp to reduce device clock skew.

A real upward bid creates `bidRaised` and adds exactly the configured extension (MVP: 5 seconds), regardless of the bid amount. A manual correction does not extend the timer.

Undo has deterministic clock semantics:

- undo bid raise: remove exactly the extension added by that raise while preserving `started_at`;
- undo price correction: preserve the clock unchanged;
- undo nomination: clear the clock;
- undo assignment/skip/unavailable: reopen the call with a fresh countdown.

## Controller lease

`live/current.controller_instance_id` identifies the owner app instance that may mutate the auction.

Every mutation uses a Firestore transaction that:

1. reads the live state;
2. verifies controller ownership;
3. validates the transition against the current server-side live state;
4. assigns the next server revision;
5. writes event, session metadata and live state atomically.

The client also mirrors the lease before applying optimistic events. A viewer therefore cannot create even a temporary local "ghost" mutation before Firestore rejects the write.

Another device authenticated as the owner may explicitly claim control. Claiming control does not reset the timer. Cross-account members are viewer-only: Security Rules prevent them from changing `live`, events, player snapshots or session membership.

## Secure sharing

Sharing uses a two-phase owner-approved protocol.

1. The owner creates a 192-bit random invite token stored at `auction_sessions/{id}/private/sharing`.
2. The share payload contains `session`, `owner` and the token using the `astamatrix://join` URI scheme.
3. The recipient creates an `auction_join_requests/{sessionId}--{uid}` request.
4. Only the requester and the indicated owner can read that request.
5. The owner validates the current private invite token, assigns the requester to one auction team, adds the UID to `member_uids` and approves the request in a transaction.
6. The approved member can read the session snapshot, event log and live clock, but remains unable to mutate them.

Invite secrets remain in the owner-only `private` subcollection, so joining the auction never exposes the reusable token to other members.

## Player data independence and compatibility

Schema 7 is the minimum supported independent session format. Every supported auction contains its own `auction_sessions/{id}/players` snapshot.

The old global `/players` collection is no longer read by the runtime and is denied by Firestore Security Rules. Pre-schema-7 sessions are intentionally rejected with a migration message instead of reopening the legacy global-catalog dependency.

Internal prototype type names can be renamed after the MVP without changing the public data-source boundary.
