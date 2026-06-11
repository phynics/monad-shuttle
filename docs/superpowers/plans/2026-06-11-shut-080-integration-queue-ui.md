# SHUT-080: Integration Queue UI

## Goal

Provide the first operator screen for Shuttle: a deployable queue view that shows server status, repository state, active shard groups, open conflicts, and recent events.

## Scope

- Keep UI source in the separate `ShuttleWebUI` target.
- Serve the static UI bundle from `ShuttleServer` at `/`.
- Add static asset routes for CSS and JavaScript.
- Poll existing REST endpoints:
  - `/api/status`
  - `/api/shards`
  - `/api/conflicts`
  - `/api/events?limit=8`
- Group shards by `running`, `needs_input`, `integrating`, and `done`.
- Add empty and error states.
- Add tests for asset generation and server route delivery.

## Notes

- The UI is static HTML/CSS/JavaScript for v1. This avoids adding a frontend toolchain before the workflow needs it.
- The first screen is the operational queue, not a landing page.
- Visual treatment is restrained and dense enough for repeated operator use.

## Verification

- `swift test --filter ShuttleWebUISmokeTests`
- `swift test --filter ShuttleOperatorUIRouteTests`
- `swift test`
- `swift build`
