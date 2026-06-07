# SHUT-033: Merge-Based Upstream Refresh

## Goal

Fetch the configured upstream branch and merge it into `shuttle-main` without reset or rebase.

## Scope

- Add an upstream refresh service that:
  - fetches `origin/<sourceBranch>`
  - enters repository state `refreshing`
  - performs a non-rebase merge into `shuttle-main`
  - returns the repository to `open` on clean refresh or no-op
  - records an `upstream_refresh` conflict and leaves the repo `blocked` on merge conflict
- Persist refreshed upstream and `shuttle-main` commit pointers in repository state.
- Cover clean refresh, no-op, and conflict cases with real git fixtures.

## Notes

- The refresh service uses a temporary `shuttle-main` worktree so the merge happens through ordinary git mechanics rather than ref mutation shortcuts.
- Any nonzero merge command in this controlled path is treated as a conflict for v1. That keeps the behavior deterministic with the current git shell abstraction.

## Verification

- `swift test --filter ShuttleUpstreamRefreshServiceTests`
- `swift test`
- `swift build`
