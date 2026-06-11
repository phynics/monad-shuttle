# SHUT-073: Conflict, Refresh, And Push APIs

## Goal

Expose the remaining operator-facing repository control APIs for conflict inspection and resolution, manual refresh, and manual push.

## Scope

- Add `GET /api/conflicts` for open and resolved conflict records.
- Add `POST /api/conflicts/{id}/resolve`.
- Add `POST /api/repository/refresh`.
- Add `POST /api/pushes` with idempotency-key support.
- Add conflict, refresh, and push response/request models.
- Extend the conflict store with an all-conflicts read helper.
- Map repository, conflict, refresh, and push domain errors to stable HTTP responses.
- Add router tests for:
  - conflict listing with open and resolved records
  - successful conflict resolution
  - refresh blocked by repository state
  - push idempotency and push audit recording

## Notes

- Refresh remains synchronous in v1 and returns the immediate outcome from the existing refresh service.
- Push request refs are intentionally narrow in v1: `shuttle_main` and `retained_shard`.
- Conflict resolution surfaces repository cleanliness and active-merge validation failures as `400 Bad Request`, preserving the existing manual-operator model without hiding the reason.

## Verification

- `swift test --filter ShuttleRepositoryOperationsAPITests`
- `swift test`
- `swift build`
