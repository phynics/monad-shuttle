# SHUT-064: Manual Push Actions

## Goal

Allow authenticated clients to explicitly push `shuttle-main` or retained shard branches to configured targets, with idempotency and audit coverage.

## Scope

- Add a typed push service for:
  - `shuttle-main`
  - retained shard branches
- Require configured push target lookup.
- Require idempotency keys and replay prior responses on duplicate requests.
- Record push audit events with warning metadata.
- Warn, but do not block, when repository state is risky, such as `blocked`.

## Notes

- V1 warning metadata is derived from repository integration state. That satisfies the milestone requirement without widening the policy surface to arbitrary host-side risk probes.
- Pushes are implemented from the bare repository with explicit local-ref to remote-ref mapping.

## Verification

- `swift test --filter ShuttlePushServiceTests`
- `swift test`
- `swift build`
