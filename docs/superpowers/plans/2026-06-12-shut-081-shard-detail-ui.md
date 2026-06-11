# SHUT-081: Shard Detail UI

## Goal

Allow operators to inspect an individual shard and take the v1 shard actions from the browser UI.

## Scope

- Serve the same static UI shell for `/shards/{id}`.
- Detect shard-detail routes client-side.
- Load shard detail, shard events, shard logs, and completion report data.
- Add `GET /api/shards/{id}/completion-report` for the detail screen.
- Show shard status, spec, branch, worktree path, container status, completion report, events, and logs.
- Show request-finish and abandon actions for running shards.
- Show answer form for `needs_input` shards.
- Refresh detail state after actions.
- Add tests for static asset coverage, route serving, and completion-report API response.

## Notes

- The detail view remains in the same static bundle as SHUT-080. That keeps navigation simple without introducing a frontend router package.
- The completion report endpoint returns `404` when a shard has no report; the UI treats that as an empty detail section.

## Verification

- `swift test --filter ShuttleWebUISmokeTests`
- `swift test --filter ShuttleOperatorUIRouteTests`
- `swift test --filter ShuttleShardAPITests`
- `swift test`
- `swift build`
