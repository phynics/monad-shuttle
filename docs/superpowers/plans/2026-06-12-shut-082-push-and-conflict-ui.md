# SHUT-082: Push And Conflict UI

## Goal

Allow operators to resolve conflicts and manually push configured refs from the browser UI.

## Scope

- Extend the queue screen conflict panel with a resolve action.
- Extend the queue screen with a push panel listing configured push targets from `/api/config`.
- Push `shuttle-main` to a selected configured target via `/api/pushes`.
- Generate an idempotency key for each browser-initiated push.
- Display a warning confirmation before pushing while the repository is not `open`.
- Add static asset tests for conflict resolution controls, push controls, warning behavior, and idempotency header usage.

## Notes

- V1 pushes only expose `shuttle_main` from the UI. The API still supports retained shard pushes.
- The warning is client-side and mirrors the server-side push behavior: risky repository states warn but do not block operator action.

## Verification

- `node --check` on the embedded JavaScript asset
- `swift test --filter ShuttleWebUISmokeTests`
- `swift test`
- `swift build`
