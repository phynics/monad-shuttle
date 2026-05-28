# Shuttle Design

Date: 2026-05-28
Status: Draft for review

## Purpose

Shuttle is a standalone coding-environment service for supervised autonomous software work. It is a sibling project to `Monad` and `PositronicKit`, not a target inside Monad.

Monad remains the personal agent. Shuttle owns repository execution: bare clone management, `shuttle-main`, shard worktrees, shard agents, per-worktree containers, integration, retention, and operator/API control surfaces. Monad or other clients may later create shards or attach to Shuttle workspaces through Shuttle's API.

## Technical Foundation

Shuttle v1 is a Swift package and Docker-deployable service using the same broad server stack as Monad:

- SwiftPM package
- Hummingbird REST server
- GRDB/SQLite persistence
- PositronicKit for agent runtime, workspace abstractions, tools, and prompt assembly
- Docker socket access for per-worktree execution containers

The first release manages exactly one configured git repository per Shuttle deployment. Multiple repositories are future work.

## Product Boundary

Shuttle is the coding environment. It:

- clones the configured upstream repository as a bare repo
- imports an operator-designated upstream branch
- creates and maintains a local-only `shuttle-main` integration branch
- creates one git worktree per shard
- runs PositronicKit shard agents inside the Shuttle server process
- executes shard filesystem, git, and command tools only inside each shard's worktree/container boundary
- provides REST APIs and a built-in local/admin web UI
- supports explicit manual push actions to configured remote targets

Shuttle-managed refs are local by default. `shuttle-main`, normal shard branches, and system shard branches are not pushed automatically.

## Core Concepts

### Repository

The single configured git repository for the deployment. Configuration comes from a mounted YAML file. It includes:

- repo URL
- source branch
- SSH key path
- container image
- container working directory
- command policy
- upstream refresh schedule
- retention window
- allowed or default push targets
- API authentication settings
- Shuttle instruction file path

On startup, Shuttle validates existing volumes, validates the SSH key path, verifies Docker access, fetches upstream, creates or validates the bare repo, and creates or validates `shuttle-main`.

### Management Workspace

The management workspace is a PositronicKit-compatible workspace representing repo-level orchestration. It exposes tools for:

- listing shards
- creating shards from specs
- inspecting repo, queue, integration, and log state
- retrying safe failed setup or integration operations
- refreshing upstream
- pushing refs to configured targets
- abandoning or archiving retained shards

It does not expose raw bare-repo internals as the normal tool surface.

### Shard

A shard is Shuttle's unit of work. A shard has:

- one spec or instruction payload
- one human-readable local branch
- one git worktree
- one long-lived per-worktree execution container
- one PositronicKit agent lifecycle
- one combined lifecycle status
- one append-only event log
- optional follow-up shard proposals

Normal shards are created by UI/API requests. System shards are created automatically for upstream refresh conflicts or shard merge conflicts.

### Shard Workspace

Each shard worktree is exposed as a PositronicKit-compatible workspace. A shard workspace exposes:

- filesystem tools
- git status/diff/log tools
- command tools
- lifecycle tools such as `finish_shard` and `abandon_shard`
- log and check-report inspection tools

Hard invariant: a shard agent has no direct host filesystem access and no host shell access. Every file, git, and command tool resolves inside the shard worktree working directory. Command execution happens only through `docker exec` inside that shard's container.

The Shuttle server may perform privileged orchestration internally, such as creating worktrees, merging into `shuttle-main`, cleaning retained files, and pushing refs. Those privileges are not ambient capabilities for shard agents.

## State Machines

### Server State

- `booting`: process is alive, config not yet validated
- `initializing_repo`: config, volumes, SSH key, Docker, bare repo, upstream fetch, and `shuttle-main` are being validated or created
- `ready`: API/UI available; shards can run; repo integration may still be blocked
- `degraded`: API/UI available, but a subsystem is impaired; unsafe operations return explicit errors
- `draining`: shutdown requested; no new shards start; active operations receive a graceful stop window
- `fatal`: startup cannot continue because required config, storage, Docker, or git prerequisites are invalid

`degraded` is a real server state and should also expose detailed subsystem health for Docker, git, database, repo refresh, agent runtime, and filesystem volumes.

### Repository Integration State

- `open`: `shuttle-main` accepts shard integrations
- `refreshing`: scheduled or manual upstream refresh is in progress
- `integrating`: a finished shard is being squash-merged into `shuttle-main`
- `blocked`: integration is closed because a system shard must resolve an upstream or shard merge conflict

Invariant: `blocked` points to exactly one active system shard. Running shards may continue, but no shard transitions into integration while the repository is `blocked`.

### Shard State

- `queued`: shard accepted but not started
- `running`: shard has or is acquiring its worktree/container and the agent is active or resumable
- `needs_input`: agent is paused with a concrete question or blocker; UI/API can answer and resume it
- `integrating`: agent called `finish_shard`; Shuttle owns merge processing
- `done`: shard was squash-merged into `shuttle-main`
- `failed`: unrecoverable tool, process, git, or orchestration failure
- `abandoned`: explicitly stopped by UI/API/operator action

Retention is metadata, not a shard status. A `done` shard has `retainedUntil`; after the retention window, Shuttle removes retained worktree files and local shard branches while preserving logs and metadata.

## Shard Lifecycle

1. A human or API client creates a shard with a spec.
2. Shuttle records the shard as `queued`.
3. Shuttle creates a human-readable local branch from current `shuttle-main`.
4. Shuttle creates a worktree for that branch.
5. Shuttle starts a long-lived per-worktree container from the configured image.
6. Shuttle runs a PositronicKit agent in the Shuttle server process.
7. The agent receives deterministic context:
   - Shuttle deployment instructions from mounted config
   - repo-native guidance such as `AGENTS.md`, if present
   - the shard spec
8. The shard runs until it calls `finish_shard`, asks for input, fails, or is abandoned.

If the agent appears done but has not called `finish_shard`, Shuttle sends one system warning instructing it to run appropriate checks and either call `finish_shard` or explain the blocker. If it cannot finish and provides a blocker/question, the shard moves to `needs_input`.

`finish_shard` requires a structured completion report:

- summary
- files changed
- checks run by the agent
- known risks
- follow-up shard proposals

V1 relies on the shard agent to run appropriate checks. Shuttle verifies git state and mergeability, but it does not own configured check suites yet.

## Integration

When a shard calls `finish_shard`, Shuttle moves it to `integrating`. If repository integration state is `blocked`, the shard waits. If integration is open, Shuttle verifies the shard worktree and attempts a squash merge into local `shuttle-main`.

The squash commit message is generated from the structured completion report. The original shard branch and worktree remain available read-only for seven days after successful integration. Logs and metadata are retained indefinitely.

If a normal shard merge conflicts, Shuttle:

1. creates a visible system shard with generated conflict-resolution instructions
2. sets repository integration state to `blocked`
3. allows active shard work to continue
4. prevents further shard integration until the system shard completes

The system shard runs with an agent automatically. When it calls `finish_shard`, Shuttle integrates the conflict resolution into `shuttle-main` and unblocks the repository if successful.

## Upstream Refresh

Shuttle periodically fetches the configured upstream branch according to YAML config. It attempts to integrate upstream changes into local `shuttle-main`.

If the refresh applies cleanly, `shuttle-main` advances and future shards start from the updated integration line.

If the refresh conflicts, Shuttle creates a system shard with generated instructions describing:

- upstream source branch and commit
- current `shuttle-main`
- conflict context
- desired resolution outcome

Repository integration state becomes `blocked`. Existing running shards continue, but no shard can integrate until the system shard completes.

## Push Actions

V1 includes explicit manual push actions through UI/API. Authenticated clients may push:

- `shuttle-main`
- retained individual shard branches

Push targets are operator-defined in YAML config. Shuttle warns if the repository is blocked, dirty, or otherwise risky, but v1 does not prevent authenticated clients from performing operator push actions. Push actions are always audited.

Fine-grained authorization is future work. V1 treats authenticated API clients as operator-capable.

## API

Shuttle v1 is REST-only. There is no SSE or WebSocket in v1. The UI polls REST endpoints for queue and log updates.

The API covers:

- server and repository status
- health details
- effective read-only config with secrets redacted
- shard creation
- shard listing and filtering
- shard detail
- answering `needs_input`
- abandoning shards
- retrying safe failed setup/integration operations
- paginated shard and repo event logs
- management and shard workspace references/tool metadata in PositronicKit-compatible terms
- manual upstream refresh
- integration state inspection
- push actions

## UI

The built-in UI is a local/admin operator surface that consumes the same REST API. V1 does not include a separate human login/session layer.

The first screen is the Integration Queue. It shows:

- server state
- repository integration state
- blocked reason and active system shard, if any
- running shards
- shards needing input
- shards integrating
- recently completed shards
- recent refresh and push events

Shard detail pages show:

- current status
- spec
- agent transcript and tool log, polled from REST
- command output
- git summary
- completion report
- retained worktree status
- answer box when status is `needs_input`
- follow-up shard proposals awaiting confirmation

Follow-up shards proposed by agents are never created automatically. A human or API client must confirm them.

## Persistence

Shuttle uses GRDB/SQLite for durable metadata, lifecycle events, audit records, and indexes into larger log artifacts. Raw transcripts and command output live in the log volume.

SQLite records:

- server/repo state snapshots
- shard records
- system shard relationships
- branch/worktree/container metadata
- completion reports
- follow-up proposals
- audit events
- append-only lifecycle and log indexes

The API treats lifecycle events and raw logs as append-only.

## Deployment Volumes

Shuttle uses separate mounted volumes:

- database volume: SQLite and migrations
- git volume: bare repo and local refs
- worktree volume: active and retained shard worktrees
- log volume: append-only shard and repo logs retained indefinitely
- config volume: YAML config and Shuttle instruction file
- secrets volume: SSH key material

SSH private keys remain in the secrets volume and are never copied into SQLite. SQLite stores only credential path references and redacted metadata.

## Startup And Recovery

Startup is idempotent:

1. load mounted YAML config
2. validate config schema
3. validate volumes
4. validate SSH key path
5. validate Docker socket access
6. validate or create bare clone
7. fetch upstream
8. validate or create local `shuttle-main`
9. reconcile database records with git/worktree/container reality
10. enter `ready` or `degraded`

If required prerequisites are invalid, Shuttle enters `fatal`.

Recovery rules:

- SQLite is the source of truth for shard lifecycle, audit history, and log indexes.
- Git refs and worktrees are reconciled against SQLite on startup.
- Missing retained worktrees are logged but do not corrupt `done` shards.
- Running shards found after restart become resumable `running` if their worktree exists.
- Containers are recreated from config when needed.
- Shards found in `integrating` are inspected and either completed, returned to `running`, moved to `needs_input`, or marked `failed` with an explanatory event.
- Repository `blocked` state is reconstructed from the active system shard pointer and git merge state.
- Cleanup periodically removes retained worktree files and local shard branches after seven days, preserving logs and metadata.

## Security And Safety Invariants

- Shard agents never receive host shell access.
- Shard agents never receive direct host filesystem access.
- Shard filesystem tools resolve only inside the shard worktree.
- Shard git tools operate only inside the shard worktree.
- Shard command execution happens only via `docker exec` inside the shard container.
- Shuttle-managed refs stay local unless an authenticated client explicitly pushes.
- Mounted SSH key material is redacted from all API/UI/log output.
- SSH key material is not stored in SQLite.
- Pushes are manual, audited, and target only configured destinations.
- Retained worktrees become read-only after merge.

## Testing Strategy

V1 tests should emphasize state transitions, tool scoping, and recovery.

Core coverage:

- YAML config parsing and redaction
- startup idempotency for fresh and existing repo volumes
- server state transitions
- repository integration state transitions
- shard lifecycle state transitions and invalid transitions
- invariant that `blocked` points to exactly one active system shard
- human-readable branch naming and collision handling
- worktree creation from `shuttle-main`
- shard filesystem/git/command tools cannot escape the shard workdir/container
- `finish_shard` report validation
- squash merge commit message generation
- merge conflict handling creates system shards and blocks integration
- upstream refresh conflict handling
- startup reconciliation for `running`, `integrating`, `done`, and retained shards
- manual push audit logging and warning behavior
- REST contract tests for queue, shard detail, logs, answer/resume, and push actions

## Deferred Work

- multiple repositories per Shuttle deployment
- separate human login/session layer for UI
- fine-grained API scopes and permissions
- configured check suites owned by Shuttle
- SSE/WebSocket log streaming
- independent worker containers that run agent loops
- secret backend integrations beyond mounted SSH keys
- richer Monad integration
