# Legacy migration

Asta Matrix now treats schema 7 as the minimum supported independent session format.

Every supported session contains its own player snapshot in `auction_sessions/{sessionId}/players`. The runtime no longer loads, reads or migrates from the old global `/players` catalog.

Sessions older than schema 7 are rejected with an explicit compatibility message asking the user to create a new auction and import a source-agnostic dataset. This is intentional: reopening the global catalog bridge would reintroduce the dependency that the independent product architecture removed.

The old `FirestorePlayerRepository`, `legacyPlayersProvider` and player repository contract have been removed from the runtime. Firestore Security Rules also deny client access to global `/players`.

If historical pre-schema-7 sessions ever need archival conversion, that conversion should be performed by a trusted administrative migration tool outside the public client, never by relaxing client Security Rules again.
