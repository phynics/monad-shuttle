# Shuttle V1 Release Notes

This document captures the current Shuttle v1 boundary and its known limitations.

## Included In V1

- one repository per Shuttle server
- bare managed repository bootstrap
- local `shuttle-main` integration branch
- shard creation with one worktree per shard
- one container per shard worktree
- shard-scoped file and git tools
- PositronicKit-based shard agent runner
- completion reports and integration gate
- squash merge into `shuttle-main`
- conflict records and manual conflict resolution
- manual push actions to configured targets
- REST APIs for status, config, shards, logs, events, conflicts, refresh, and push
- local/admin operator UI for queue, shard detail, logs, conflicts, and push
- startup reconciliation, retention cleanup, and concurrency limits
- local fixture end-to-end scenario coverage

## Known V1 Limitations

- one repository only per Shuttle instance
- no multi-node or distributed worker execution
- no fine-grained auth or per-user authorization model
- no automatic push to upstream remotes
- no automatic conflict-resolution shard creation
- no Shuttle-owned CI or independent validation runner
- agent success still depends on the agent honoring repo guidance and reporting checks accurately
- shard tools expose only the current scoped file and git surfaces; there is no general operator shell inside the agent toolset
- Docker execution assumes a local Docker socket mounted into the Shuttle server
- Docker image builds currently assume a `monad-project/` checkout containing sibling `Shuttle/` and `PositronicKit/` directories

## Verification Gate

V1 release readiness expects:

- `swift build`
- `swift test`
- Docker image build
- end-to-end fixture scenario pass
- UI smoke tests pass

## Related Docs

- [README](/Volumes/Development/monad-project/Shuttle/README.md)
- [docs/deployment.md](/Volumes/Development/monad-project/Shuttle/docs/deployment.md)
- [docs/operations.md](/Volumes/Development/monad-project/Shuttle/docs/operations.md)
