# SHUT-071: Shard APIs

## Goal

Expose the first shard-management REST API surface for creation, listing, inspection, and basic operator actions.

## Scope

- Add `POST /api/shards` with idempotency-key support.
- Add `GET /api/shards` with optional state filtering.
- Add `GET /api/shards/{id}` for shard detail.
- Add operator action endpoints:
  - `POST /api/shards/{id}/request-finish`
  - `POST /api/shards/{id}/answer`
  - `POST /api/shards/{id}/abandon`
- Extend the shard store with list and detail reads that join runtime metadata.
- Add create and answer services to keep HTTP wiring thin and state transitions explicit.
- Map domain errors to stable client-facing HTTP statuses.
- Add router tests for:
  - idempotent create replay
  - list and filter behavior
  - detail reads
  - valid action transitions
  - invalid requests and invalid transitions

## Notes

- Create uses immutable shard IDs for identity and keeps branch naming derived from existing runtime metadata.
- The answer endpoint only allows `needs_input -> running`, which gives the paused-agent flow a stable API contract without introducing broader resume semantics yet.
- Invalid shard-state filters now fail fast with `400 Bad Request` instead of being silently ignored.
- Date fields in shard API tests are decoded with ISO-8601, matching the Hummingbird response encoding used by the server.

## Verification

- `swift test --filter ShuttleShardAPITests`
- `swift test`
- `swift build`
