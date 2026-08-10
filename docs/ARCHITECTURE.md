# Asta Matrix architecture

## Boundaries

Asta Matrix keeps four concerns separate:

1. **Player data source** — user import today, Matrix data source later.
2. **Auction domain** — deterministic commands, events, reducer and advisor.
3. **Persistence** — isolated Firestore session snapshots and immutable events.
4. **Realtime coordination** — one controller instance, many viewers, shared server-clock countdown.

The domain does not require a global third-party player catalog to create new sessions.

## Session lifecycle

```text
import -> setup -> session snapshot -> live auction -> completed
```

Creating a session writes metadata first, initializes `live/current`, persists the player snapshot in bounded batches, and finally marks the snapshot ready. Event streaming begins only after the initial cloud save is confirmed.

## Event sourcing

Auction mutations are append-only events. The reducer rebuilds the effective state from the initial session snapshot plus the event sequence. Undo is represented by a compensating `eventReverted` event rather than destructive deletion.

New realtime events receive a monotonically increasing `server_revision`. Legacy events without a revision are replayed before revisioned events.

## Realtime clock

The cloud stores:

- server `started_at`;
- accumulated extension seconds;
- current bid;
- active player;
- revision;
- controlling app instance.

Clients render the countdown locally. No per-second Firestore writes are required. Each device calibrates its local clock against the latest Firestore server timestamp to reduce device clock skew.

A real upward bid creates `bidRaised` and adds exactly the configured extension (MVP: 5 seconds). A manual downward correction does not extend the timer.

## Controller lease

`live/current.controller_instance_id` identifies the app instance that may mutate the auction.

Every mutation uses a Firestore transaction that:

1. reads the live state;
2. verifies controller ownership;
3. validates the transition against the current server-side live state;
4. assigns the next server revision;
5. writes event, session metadata and live state atomically.

A viewer may explicitly claim control. Claiming control does not reset the timer. The old controller is rejected on its next attempted mutation and reloads authoritative state.

## Compatibility

The old global `/players` collection is a read-only migration bridge. Schema 7 sessions use their own `auction_sessions/{id}/players` snapshot. Opening an older session can migrate it into the new per-session representation.

Internal type names retained from the prototype can be renamed after the MVP without changing the public data-source boundary.
