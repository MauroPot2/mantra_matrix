# Legacy migration

Session schemas older than 7 are restored with the legacy player catalog when necessary. Once restored successfully, the repository writes the player snapshot into the session-scoped `players` subcollection and initializes the schema-7 live document.

The global `/players` collection remains read-only during this compatibility window. New sessions never use it as their data source.

After all relevant legacy sessions have been completed or migrated and verified, the global legacy bridge can be removed together with `FirestorePlayerRepository` and `legacyPlayersProvider`.
