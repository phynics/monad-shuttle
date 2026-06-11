# SHUT-092 Retention Cleanup

## Goal

Clean expired retained shard worktrees, remove expired local shard branches when safe, and expire raw log files and indexes according to config.

## Scope

- Add a runtime cleanup service that:
  - finds `done` shards whose `retainedUntil` is in the past
  - removes their retained worktree directories
  - removes their local shard branches
  - keeps shard metadata and audit history intact
  - expires command and agent raw logs through the existing log index model
- Invoke cleanup during startup after reconciliation.
- Add focused tests for expired worktree cleanup, branch cleanup, and raw log cleanup.

## Notes

- Cleanup only deletes local shard branches for `done` shards past retention.
- Metadata remains in SQLite after cleanup so the shard still appears as historical state.
- Startup invocation is sufficient for v1; no background scheduler is introduced here.

## Verification

- `swift test --filter ShuttleRetentionCleanupServiceTests`
- `swift test`
- `swift build`
