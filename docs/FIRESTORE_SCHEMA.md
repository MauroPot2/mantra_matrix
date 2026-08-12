# Firestore schema

```text
auction_sessions/{sessionId}
  schema_version
  owner_uid
  member_uids
  member_team_ids
  name
  status
  config
  my_team_id
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

auction_sessions/{sessionId}/private/sharing
  owner_uid
  session_id
  enabled
  token
  updated_at

auction_join_requests/{sessionId}--{requesterUid}
  session_id
  owner_uid
  requester_uid
  invite_token
  status
  assigned_team_id
  created_at
  updated_at
```

## Access rules

- Session owner: read/write session-scoped state according to the controller lease.
- Approved members: read session, player snapshot, events and live clock; no auction mutations.
- `private/*`: owner-only, including the reusable invite token.
- Join requests: visible only to requester and target owner; only the owner may approve/reject.
- Global `/players`: no client access. Supported sessions use their per-auction player snapshot.

Schema 7 is the minimum supported independent session format.
