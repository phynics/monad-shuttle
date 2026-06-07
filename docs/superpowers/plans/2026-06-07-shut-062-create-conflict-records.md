# SHUT-062: Create Conflict Records

## Goal

Persist visible conflict records for shard merge and upstream refresh failures, and block repository integration while those conflicts remain open.

## Scope

- Add a conflict persistence store on top of the existing `conflicts` table.
- Add a conflict service that creates blocking conflict records and updates repository integration state to `blocked`.
- Wire squash-merge flow so a mergeability failure becomes a shard merge conflict record instead of a generic merge error.
- Cover blocked-repository behavior with focused tests.

## Notes

- `SHUT-060` already detects non-mergeable shard branches at the integration gate. For v1, that condition is treated as a merge conflict and converted into a blocking conflict record.
- Upstream refresh conflict handling is implemented as a service entry point now; the refresh executor itself remains separate work.

## Verification

- `swift test --filter ShuttleConflictServiceTests`
- `swift test`
- `swift build`
