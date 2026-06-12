# Shuttle Operations

This runbook describes how to operate Shuttle v1 after deployment.

## Core Model

Shuttle manages one repository. The server keeps:

- a bare managed repository
- a local `shuttle-main` branch for integration
- one shard worktree per shard
- one container per shard worktree

Operators and API clients create shards, inspect shard state, resolve conflicts, and manually push configured refs.

## Shard Lifecycle

Shard states:

- `queued`
- `running`
- `needs_input`
- `integrating`
- `done`
- `failed`
- `abandoned`

Typical path:

1. shard is created in `queued`
2. agent run moves it to `running`
3. agent either requests input, fails, is abandoned, or calls `finish_shard`
4. `finish_shard` stores a completion report and moves the shard to `integrating`
5. successful squash merge moves the shard to `done`
6. retained worktree stays available until the retention deadline

## Repository Integration State

Repository integration states:

- `open`
- `refreshing`
- `integrating`
- `blocked`

Meaning:

- `open`: refresh and shard integration are allowed
- `refreshing`: upstream refresh is in progress
- `integrating`: one shard merge is in progress
- `blocked`: conflict resolution is required before new integrations

Only one integration runs at a time in v1.

## Creating And Running Shards

Operators can create shards through the API or UI. Each shard gets:

- a stable internal shard ID
- a human-readable branch name derived from title/spec plus suffix
- a worktree under `/data/worktrees`
- a container mounted to that worktree

The shard agent receives:

- Shuttle instruction file contents
- optional repository `AGENTS.md` guidance
- shard-scoped file and git tools
- shard lifecycle tools

## Completion And Integration

Before a shard can merge, Shuttle requires:

- a completion report
- at least one validation command status in that report
- no unstaged worktree changes
- no unreported untracked files
- a mergeable shard branch
- repository integration state `open`

Successful integration uses a squash merge into `shuttle-main`. Shuttle then:

- marks the shard `done`
- records `retainedUntil`
- makes the worktree read-only

## Conflict Records

V1 creates conflict records for:

- shard merge conflicts
- upstream refresh conflicts

When a blocking conflict exists, Shuttle sets repository state to `blocked`. Running shards may continue, but no new shard can integrate until the conflict is resolved.

Conflict resolution is manual in v1. Shuttle does not auto-run a conflict-resolution shard.

## Resolving Conflicts

To resolve a conflict:

1. manually repair `shuttle-main`
2. ensure the repository is clean
3. ensure no active merge state remains
4. mark the conflict resolved through the API/UI

If other blocking conflicts remain open, Shuttle stays `blocked`.

## Manual Push Actions

Pushes are explicit operator/API actions only. Shuttle does not auto-push managed refs.

V1 supports pushing:

- `shuttle-main`
- retained shard branches through the API

Push actions require:

- a configured push target
- an idempotency key

If the repository is blocked or otherwise risky, Shuttle warns but does not block the push. Pushes are always audited.

## Cleanup And Retention

V1 retention behavior:

- completed shard worktrees are kept until `retainedUntil`
- expired retained worktrees are removed during cleanup
- raw logs are removed after retention cutoff and rotated by max size
- shard metadata remains in SQLite after cleanup

Startup runs retention cleanup automatically after reconciliation.

## Recovery Behavior

On startup Shuttle reconciles persisted state against:

- the managed repository
- shard worktree presence
- conflict records
- Docker container state

Examples:

- open blocking conflicts restore repository state to `blocked`
- a missing running-shard worktree marks that shard `failed`
- an integrating shard already represented in `shuttle-main` becomes `done`
- a missing shard container for a runnable shard is recreated

## Useful Operator Checks

Use these checks first when something looks wrong:

1. `GET /api/status`
2. `GET /api/config`
3. `GET /api/shards`
4. `GET /api/conflicts`
5. `GET /api/shards/{id}`
6. `GET /api/shards/{id}/logs`
7. `GET /api/events`

## Common Recovery Cases

### Shard Stuck In `needs_input`

- inspect shard detail and logs
- provide the required answer through the API/UI
- rerun the shard agent

### Repository Stuck In `blocked`

- inspect open conflict records
- manually repair `shuttle-main`
- resolve each open conflict

### Container Problems

- check Docker subsystem health in status
- confirm Docker socket mount is present
- retry shard run or recreate the shard container path through normal workflow

### Worktree Missing

- check startup reconciliation events
- inspect shard state
- recreate work with a new shard if the original has already failed and the worktree is gone

## Local Fixture Verification

The repo includes an end-to-end local fixture scenario:

- [Tests/ShuttleServerTests/ShuttleEndToEndFixtureScenarioTests.swift](/Volumes/Development/monad-project/Shuttle/Tests/ShuttleServerTests/ShuttleEndToEndFixtureScenarioTests.swift)

It covers:

- shard creation
- fake agent execution
- completion reporting
- squash merge into `shuttle-main`
- manual push to a local remote
- blocking merge-conflict handling

Run it with:

```bash
swift test --filter ShuttleEndToEndFixtureScenarioTests
```

## Related Docs

- [README](/Volumes/Development/monad-project/Shuttle/README.md)
- [docs/deployment.md](/Volumes/Development/monad-project/Shuttle/docs/deployment.md)
- [example config](/Volumes/Development/monad-project/Shuttle/deploy/config/shuttle.example.yaml)
