# SHUT-063: Resolve Conflict Records Manually

## Goal

Allow operators to mark conflict records resolved after manually correcting `shuttle-main`, while preventing repository reopening until validation passes and no blocking conflicts remain.

## Scope

- Extend the conflict store with record lookup and resolution updates.
- Add repository validation for manual conflict resolution:
  - `shuttle-main` must be clean
  - no active merge state may remain
- Reopen the repository only when the last blocking conflict is resolved.
- Audit successful conflict resolution events.

## Notes

- The repository validator is injected into the conflict service so invalid-resolution behavior can be tested directly without manufacturing fragile git states in test fixtures.
- Partial resolution keeps the repository `blocked` and advances `blockedConflictID` to the next remaining blocking conflict.

## Verification

- `swift test --filter ShuttleConflictServiceTests`
- `swift test`
- `swift build`
