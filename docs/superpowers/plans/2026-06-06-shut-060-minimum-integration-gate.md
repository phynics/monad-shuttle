# SHUT-060: Enforce Minimum Integration Gate

- [x] Add focused tests for each gate rejection reason and one passing case.
- [x] Implement repository-state persistence for integration state checks.
- [x] Implement the integration gate service for completion-report, validation-status, worktree cleanliness, untracked-file, repository-state, and mergeability checks.
- [x] Use explicit git queries for unstaged and untracked paths, and a disposable merge attempt against `shuttle-main` for mergeability.
- [ ] Verify with `swift test --filter ShuttleIntegrationGateServiceTests`, `swift test`, and `swift build`.
