# Controller lease

The MVP supports multiple realtime viewers but only one mutating app instance at a time.

The current controller is stored in `auction_sessions/{sessionId}/live/current.controller_instance_id`. A mutation transaction verifies this value before appending an event. A viewer can explicitly claim the lease; the handoff preserves the existing countdown state.

The UI mirrors the backend rule by disabling mutation controls on viewers. Backend validation remains authoritative, so a stale controller cannot create a divergent event after a handoff.
