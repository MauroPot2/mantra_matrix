# Firestore schema

```text
auction_sessions/{sessionId}
  owner_uid
  member_uids
  status
  config
  initial_player_ids
  initial_teams
  player_snapshot_status

auction_sessions/{sessionId}/players/{playerId}
  neutral player snapshot

auction_sessions/{sessionId}/events/{eventId}
  immutable auction event
  server_revision
  controller_instance_id
  server_occurred_at

auction_sessions/{sessionId}/live/current
  phase
  active_player_id
  current_bid
  started_at
  extension_seconds
  revision
  controller_instance_id
  updated_at
```

`/players/{playerId}` remains read-only solely for pre-schema-7 restore compatibility.
