# SHUT-091 Concurrency Limits

## Goal

Enforce configured queued and running shard limits, and make the single `shuttle-main` mutation lock explicit in tests.

## Scope

- Add a focused runtime limit service for shard-count checks.
- Reject shard creation when queued shard count is already at `maxQueuedShards`.
- Reject transitions into `running` when active running shard count is already at `maxRunningShards`.
- Cover the existing repository-state mutation lock with explicit tests for refresh vs integration.

## Notes

- `maxIntegratingShards` remains fixed at `1` and is enforced through repository integration state transitions rather than a second counter.
- Running-shard enforcement applies to transitions into `running`, not to already persisted running shards during recovery.

## Verification

- `swift test --filter ShuttleConcurrencyLimitServiceTests`
- `swift test --filter ShuttleShardAPITests`
- `swift test --filter ShuttleShardAgentRunnerTests`
- `swift test --filter ShuttleUpstreamRefreshServiceTests`
- `swift test --filter ShuttleSquashMergeServiceTests`
- `swift test`
- `swift build`
