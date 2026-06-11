# SHUT-072: Logs And Events APIs

## Goal

Expose cursor-paginated read APIs for shard lifecycle events, shard command-log indexes, and repo-level audit events.

## Scope

- Add forward-only pagination to the audit-event store using append-only event IDs as cursors.
- Add forward-only pagination to the command-log store using log-index row IDs as cursors.
- Add `GET /api/shards/{id}/events`.
- Add `GET /api/shards/{id}/logs`.
- Add `GET /api/events`.
- Add bounded `cursor` and `limit` parsing with client-error responses for invalid pagination input.
- Add API response models for:
  - audit event pages
  - command log pages
  - individual audit events
  - individual log chunks
- Add router tests for:
  - shard event pagination
  - shard log pagination
  - repo-level event pagination
  - missing shard responses
  - invalid pagination requests

## Notes

- Pagination is strictly append-order by SQLite row ID, which matches the append-only semantics already enforced for audit events and the insertion-order semantics of log indexes.
- `nextCursor` is the last row ID returned in the current page when more rows remain; clients can resume with `?cursor=<id>`.
- Shard log responses expose indexed chunk metadata plus the decoded command-log payload so the operator UI can render logs without a second raw-file lookup path.

## Verification

- `swift test --filter ShuttleLogsAndEventsAPITests`
- `swift test`
- `swift build`
