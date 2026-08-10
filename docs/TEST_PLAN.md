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

- Create an auction, force-close the app and reopen it.
- Verify session, teams and dataset restore without reading the global legacy catalog.
- Complete an auction and verify it no longer appears as live.

## Realtime two-device test

Use two physical devices logged into the same MVP account.

1. Open the same session on both devices.
2. Confirm one shows Controller and the other Viewer.
3. Nominate a player on the Controller.
4. Compare countdowns visually and with a screen recording.
5. Raise +1 and verify exactly +5 seconds is added on both devices.
6. Raise +5 and verify exactly one +5-second extension, not +25.
7. Enter a lower manual correction and verify the countdown is not extended.
8. On Viewer press “Prendi controllo”.
9. Confirm the previous Controller becomes Viewer without timer reset.
10. Attempt another mutation from the old controller and verify no divergent state is produced.
11. Assign the active player and verify teams, credits and roster update on both devices.
12. Test undo and verify both devices converge to the same state.

## Network resilience

- Repeat the two-device test on Wi-Fi.
- Repeat with one device on cellular data.
- Toggle airplane mode on the Viewer and reconnect; verify it catches up from Firestore.
- Toggle connectivity on the Controller before a bid; verify failed writes surface an error and the client reloads authoritative state.

## Release smoke

- Android debug build/install.
- iOS release archive.
- macOS release build if distributed.
- Login with email/password.
- Login with Google.
- Password reset.
- File import on every target platform.
