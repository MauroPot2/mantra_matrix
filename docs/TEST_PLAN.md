# Asta Matrix — MVP manual test plan

## Import

- Import comma-separated CSV.
- Import semicolon-separated CSV.
- Import TSV.
- Verify quoted names containing commas.
- Verify invalid roles are reported with row number.
- Verify duplicate generated IDs remain unique.
- Verify a new auction cannot start with an empty dataset.

## Persistence

- Create a schema-7 auction, force-close the app and reopen it.
- Verify session, teams and per-auction dataset restore without reading global `/players`.
- Complete an auction and verify it no longer appears as live.
- Interrupt connectivity while completing an auction and verify the local live session remains open when the cloud commit fails.
- Verify a pre-schema-7 session is rejected explicitly instead of triggering a global catalog read.

## Realtime two-device owner test

Use two physical devices logged into the same owner account.

1. Open the same session on both devices.
2. Confirm one shows Controller and the other Viewer.
3. Nominate a player on the Controller.
4. Compare countdowns visually and with a screen recording.
5. Raise +1 and verify exactly +5 seconds is added on both devices.
6. Raise +5 and verify exactly one +5-second extension, not +25.
7. Perform 15–25 rapid real raises and verify price/event ordering never jumps backwards and each raise contributes exactly +5 seconds.
8. Enter a lower manual correction and verify the countdown is not extended.
9. Undo a real raise and verify only that raise's +5 seconds is removed without restarting the call.
10. Undo a price correction and verify the timer is unchanged.
11. Undo a nomination and verify the clock closes.
12. Assign the player, then undo and verify the call reopens with a fresh countdown.
13. On Viewer press “Prendi controllo”.
14. Confirm the previous Controller becomes Viewer without timer reset.
15. Attempt another mutation from the old controller and verify no local ghost mutation or divergent state is produced.
16. Assign the active player and verify teams, credits and roster update on both devices.

## Cross-account sharing test

The backend protocol is already implemented; expose these actions in the UX before running this section.

1. Owner creates an invite for a schema-7 auction.
2. Confirm the share payload uses the `astamatrix://join` URI and contains a long random token.
3. A second Firebase account submits the join request.
4. Confirm the second account cannot read the auction before approval.
5. Confirm a third unrelated account cannot read the join request.
6. Owner sees the pending request, chooses an unassigned auction team and approves it.
7. Confirm the approved account now sees the shared auction and restores its per-session player snapshot/event history.
8. Confirm the approved account can observe active player, bid, teams and countdown in realtime.
9. Confirm the approved account cannot nominate, bid, assign, undo, complete the auction or write `live/current`.
10. Confirm the approved account cannot read `auction_sessions/{id}/private/sharing` or recover the reusable invite token.
11. Confirm the same team cannot be assigned to two distinct members.
12. Disable/regenerate sharing and verify an obsolete token cannot be approved.

## Network resilience

- Repeat the owner two-device test on Wi-Fi.
- Repeat with one device on cellular data.
- Toggle airplane mode on a Viewer and reconnect; verify it catches up from Firestore.
- Toggle connectivity on the Controller before a bid; verify failed writes surface an error and the client reloads authoritative state.
- Generate several rapid raises while network latency is elevated and verify confirmed events never reorder pending local events.
- Background/foreground both devices during an active countdown and verify they recalibrate from server timestamps rather than pausing local truth.

## Release smoke

- Android debug build/install.
- Android release build.
- iOS release build/archive.
- macOS release build if distributed.
- Login with email/password.
- Login with Google.
- Password reset.
- File import on every target platform.
