# Controller lease

The MVP supports multiple realtime viewers but only one mutating owner app instance at a time.

The current controller is stored in `auction_sessions/{sessionId}/live/current.controller_instance_id`. A mutation transaction verifies this value before appending an event. The client also mirrors the lease and blocks optimistic mutations before they enter local state.

Another device authenticated as the session owner may explicitly claim the lease; the handoff preserves the existing countdown state. Cross-account members are viewer-only and cannot claim control because Firestore limits `live` writes to the session owner.

Backend validation remains authoritative, so a stale controller cannot create a divergent event after a handoff. If a write is rejected, the client reloads the authoritative session rather than keeping speculative state.
