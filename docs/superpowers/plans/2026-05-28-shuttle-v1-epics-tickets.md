# Shuttle V1 Epics And Tickets

> **For agentic workers:** REQUIRED SUB-SKILL for implementation: use `superpowers:writing-plans` to expand one ticket into a task-by-task implementation plan before writing code. This document is the product backlog split from the Shuttle design spec.

**Goal:** Deliver Shuttle v1 as a safe, single-repository shard execution service with REST API, operator UI, scoped container execution, manual conflict handling, and explicit push controls.

**Architecture:** Shuttle is a standalone Swift package. The server owns repository state, shard lifecycle, PositronicKit agent execution, per-shard worktree containers, and REST API. The local/admin UI lives in a separate `ShuttleWebUI` target and consumes the same REST surface. Git, Docker, database, log, config, and secret concerns are isolated behind focused services.

**Tech Stack:** Swift 6, SwiftPM, Hummingbird, GRDB/SQLite, PositronicKit, Docker socket plus `docker exec`, mounted YAML config, mounted SSH key secrets.

---

## Milestones

1. **M1 Foundation:** package, config, persistence skeleton, health endpoint.
2. **M2 Repository Core:** bootstrap bare repo, `shuttle-main`, refs, branch naming.
3. **M3 Shard Core:** shard records, lifecycle transitions, idempotent creation, worktrees.
4. **M4 Execution Boundary:** per-shard containers, scoped tools, logs.
5. **M5 Agent Loop:** PositronicKit shard agents, finish/input/abandon flow.
6. **M6 Integration:** safety gate, squash merge, conflicts, upstream refresh, push.
7. **M7 Operator Surface:** REST completion, UI queue/detail/logs/actions.
8. **M8 Recovery And Operations:** startup reconciliation, cleanup, limits, test hardening.

## Proposed File Structure

- `Package.swift`: Swift package products, dependencies, and targets.
- `Sources/ShuttleServer/ShuttleServerApp.swift`: application entrypoint and service lifecycle.
- `Sources/ShuttleServer/HTTP/Routes.swift`: Hummingbird route registration.
- `Sources/ShuttleServer/HTTP/Controllers/*.swift`: REST controllers for status, shards, logs, conflicts, push, config.
- `Sources/ShuttleServer/Config/*.swift`: YAML config loading, validation, redaction.
- `Sources/ShuttleServer/Database/*.swift`: GRDB connection, migrations, repositories.
- `Sources/ShuttleServer/Domain/*.swift`: server, repository, shard, conflict, push, and log models.
- `Sources/ShuttleServer/Git/*.swift`: bare repo bootstrap, refs, worktrees, merge, refresh, push.
- `Sources/ShuttleServer/Runtime/*.swift`: shard orchestration, state machine, limits, recovery.
- `Sources/ShuttleServer/Docker/*.swift`: Docker socket checks, container lifecycle, `docker exec`.
- `Sources/ShuttleServer/Tools/*.swift`: shard workspace tools and scoped tool adapters.
- `Sources/ShuttleServer/Agents/*.swift`: PositronicKit agent runner and prompt/context assembly.
- `Sources/ShuttleWebUI/*.swift`: UI composition, assets, and REST-facing client layer for the operator surface.
- `Tests/ShuttleServerTests/*`: unit and integration tests.
- `docs/superpowers/specs/2026-05-28-shuttle-design.md`: source design spec.

## Epic E0: Project Foundation

### Ticket SHUT-001: Create Swift Package Skeleton

**Outcome:** `Shuttle/` builds as a standalone Swift package with a server executable and test target.

**Acceptance Criteria:**

- `swift build` succeeds from `Shuttle/`.
- `swift test` succeeds with at least one smoke test.
- Package depends on `../PositronicKit` by path.
- Package includes executable product `ShuttleServer`.
- Package includes a separate `ShuttleWebUI` target for future UI work.
- No Monad target is modified.

**Dependencies:** none.

### Ticket SHUT-002: Add Server Entrypoint And Health Route

**Outcome:** `swift run ShuttleServer` starts a Hummingbird server with a basic health endpoint.

**Acceptance Criteria:**

- `GET /api/status` returns server state `ready` for a minimal test configuration.
- The response includes subsystem health keys for database, git, docker, config, volumes, repo refresh, and agent runtime.
- The server can enter `fatal` during startup when required config is invalid.
- Graceful shutdown sets `draining` before stopping accepting new shard work.

**Dependencies:** SHUT-001.

### Ticket SHUT-003: Add Docker Deployment Skeleton

**Outcome:** Shuttle has a Dockerfile and compose example matching the volume model.

**Acceptance Criteria:**

- Dockerfile builds the `ShuttleServer` executable.
- Compose example mounts separate database, git, worktree, log, config, and secrets volumes.
- Compose example mounts Docker socket.
- Compose example documents required SSH key path and YAML config path.

**Dependencies:** SHUT-001.

## Epic E1: Configuration And Secrets

### Ticket SHUT-010: Define YAML Config Model

**Outcome:** Shuttle can load and validate the mounted YAML config.

**Acceptance Criteria:**

- Config includes repo URL, source branch, SSH key path, container image, container workdir, command policy, refresh schedule, retention, raw log retention/max size, concurrency limits, push targets, auth settings, and instruction file path.
- Missing required fields produce deterministic validation errors.
- Unknown fields produce deterministic validation errors.
- Unit tests cover valid config, missing required values, invalid paths, invalid limits, and invalid push target definitions.

**Dependencies:** SHUT-001.

### Ticket SHUT-011: Redact Config And Secrets

**Outcome:** APIs and logs expose effective config without secret material.

**Acceptance Criteria:**

- SSH key contents are never read into SQLite.
- API redaction replaces secret paths or values according to the redaction policy.
- Log output never includes private key contents.
- Tests verify redaction for config API payloads and validation errors.

**Dependencies:** SHUT-010.

### Ticket SHUT-012: Validate Volumes And SSH Key Path On Startup

**Outcome:** Startup validates deployment prerequisites before serving work.

**Acceptance Criteria:**

- Startup validates database, git, worktree, log, config, and secrets volume paths.
- Startup validates configured SSH key path exists and is readable.
- Invalid required paths produce `fatal`.
- Health details identify the exact failed subsystem.

**Dependencies:** SHUT-010, SHUT-011.

## Epic E2: Persistence And Domain State

### Ticket SHUT-020: Add Database Migrations

**Outcome:** SQLite schema supports v1 repository, shard, conflict, log index, audit, and idempotency records.

**Acceptance Criteria:**

- Migrations create tables for repository state, shard records, conflict records, branch/worktree/container metadata, completion reports, audit events, idempotency keys, and log indexes.
- Migration tests can create a fresh database and reopen it.
- Schema stores immutable shard IDs separately from branch names.
- Schema stores raw log references, not raw log contents.

**Dependencies:** SHUT-001.

### Ticket SHUT-021: Implement State Machines

**Outcome:** Server, repository, and shard transitions are explicit and validated.

**Acceptance Criteria:**

- Server states are `ready`, `draining`, and `fatal`.
- Repository states are `open`, `refreshing`, `integrating`, and `blocked`.
- Shard states are `queued`, `running`, `needs_input`, `integrating`, `done`, `failed`, and `abandoned`.
- Invalid transitions fail with structured errors.
- Tests cover valid transitions, invalid transitions, and blocked integration behavior.

**Dependencies:** SHUT-020.

### Ticket SHUT-022: Implement Audit And Lifecycle Events

**Outcome:** Important API, shard, repo, and push actions are recorded as append-only lifecycle/audit events.

**Acceptance Criteria:**

- Events include actor/client identity where available, timestamp, entity type, entity ID, event type, and structured payload.
- Events are append-only through repository APIs.
- Tests verify shard creation, finish request, input answer, abandon, conflict creation, conflict resolution, and push audit events.

**Dependencies:** SHUT-020, SHUT-021.

### Ticket SHUT-023: Implement Idempotency Records

**Outcome:** Shard creation and push actions are idempotent for retrying API clients.

**Acceptance Criteria:**

- Requests for shard creation require an idempotency key.
- Requests for push actions require an idempotency key.
- Reusing the same key with the same request returns the original result.
- Reusing the same key with a materially different request returns a conflict error.
- Tests cover duplicate request replay and mismatched request rejection.

**Dependencies:** SHUT-020.

## Epic E3: Git Repository Core

### Ticket SHUT-030: Bootstrap Bare Repository And `shuttle-main`

**Outcome:** Startup creates or validates the bare repo and local integration branch.

**Acceptance Criteria:**

- Fresh startup clones configured repo as bare.
- Existing startup validates the repo matches config.
- Startup fetches configured upstream branch.
- Startup creates `shuttle-main` from configured upstream branch when absent.
- Startup validates existing `shuttle-main` when present.
- Tests use local fixture repositories.

**Dependencies:** SHUT-010, SHUT-012, SHUT-020.

### Ticket SHUT-031: Implement Branch Naming Contract

**Outcome:** Shard branches are human-readable while shard identity remains immutable.

**Acceptance Criteria:**

- Branch names derive from shard title or spec summary.
- Branch names include a short stable suffix derived from immutable shard ID.
- Branch name collisions extend or append the ID suffix.
- APIs use immutable shard IDs, not branch names.
- Tests cover normal slugs, unsafe characters, long titles, and collisions.

**Dependencies:** SHUT-020.

### Ticket SHUT-032: Create And Retain Worktrees

**Outcome:** Shuttle creates one worktree per shard from current `shuttle-main` and retains completed worktrees read-only.

**Acceptance Criteria:**

- Shard creation records base commit.
- Worktree path is deterministic from shard ID and branch name.
- Done shard worktrees are marked read-only.
- Retained worktrees have `retainedUntil`.
- Tests cover worktree creation, duplicate prevention, and read-only retention metadata.

**Dependencies:** SHUT-030, SHUT-031.

### Ticket SHUT-033: Implement Merge-Based Upstream Refresh

**Outcome:** Shuttle can fetch upstream and merge it into `shuttle-main` without reset or rebase.

**Acceptance Criteria:**

- Refresh fetches configured upstream branch.
- Refresh attempts a non-rebase merge into `shuttle-main`.
- Clean refresh returns repository state to `open`.
- Conflicting refresh creates a conflict record and sets repository state `blocked`.
- Tests cover clean refresh, no-op refresh, and conflicting refresh.

**Dependencies:** SHUT-030, SHUT-021, SHUT-022.

## Epic E4: Containers, Scoped Execution, And Logs

### Ticket SHUT-040: Validate Docker Access

**Outcome:** Shuttle reports Docker socket health and refuses container operations when Docker is unavailable.

**Acceptance Criteria:**

- Health check verifies Docker socket access.
- Docker failure appears in subsystem health.
- Container-dependent operations fail with structured errors.
- Tests use a fake Docker client abstraction.

**Dependencies:** SHUT-002.

### Ticket SHUT-041: Manage Per-Shard Containers

**Outcome:** Each running shard has a long-lived container mounted to its worktree.

**Acceptance Criteria:**

- Container image comes from config.
- Worktree is mounted at configured container workdir.
- Container metadata is stored in SQLite.
- Container is recreated on restart when needed.
- Tests cover create, inspect, stop, and recreate flows through fake Docker client.

**Dependencies:** SHUT-032, SHUT-040.

### Ticket SHUT-042: Implement Scoped Command Execution

**Outcome:** Shard commands run only through `docker exec` in the shard container workdir.

**Acceptance Criteria:**

- No shard command API can execute on host shell.
- Every command uses configured container workdir.
- Command policy allows named tools and gated general command execution.
- Command stdout, stderr, exit code, start time, and end time are logged.
- Tests verify workdir scoping and policy rejection.

**Dependencies:** SHUT-041, SHUT-022.

### Ticket SHUT-043: Implement Raw Log Storage And Rotation

**Outcome:** Raw transcripts and command output are stored outside SQLite with configured retention or max-size rotation.

**Acceptance Criteria:**

- Raw logs are written to log volume.
- SQLite stores log indexes and metadata.
- Config can choose retention period or max size per shard.
- Cleanup applies the configured policy.
- Tests cover retention deletion, max-size rotation, and index consistency.

**Dependencies:** SHUT-020, SHUT-022.

## Epic E5: Shard Workspace Tools And Agent Runtime

### Ticket SHUT-050: Implement Shard Workspace File And Git Tools

**Outcome:** Shard workspace tools operate only inside the shard worktree.

**Acceptance Criteria:**

- File read/list/write/delete tools reject paths outside worktree.
- Git status/diff/log tools run inside shard worktree.
- Tools cannot access the bare repo path.
- Tests cover path traversal, absolute paths, symlinks, and normal file operations.

**Dependencies:** SHUT-032, SHUT-042.

### Ticket SHUT-051: Implement Shard Lifecycle Tools

**Outcome:** Agents can finish, request input, and abandon through explicit tools.

**Acceptance Criteria:**

- `finish_shard` requires structured completion report.
- `finish_shard` records validation command statuses.
- Input requests move shard to `needs_input`.
- `abandon_shard` moves shard to `abandoned` and records an audit/lifecycle event.
- Tests cover valid reports, invalid reports, input requests, and abandon.

**Dependencies:** SHUT-021, SHUT-022, SHUT-050.

### Ticket SHUT-052: Implement PositronicKit Agent Runner

**Outcome:** Shuttle can run a PositronicKit agent for a shard inside the Shuttle server process.

**Acceptance Criteria:**

- Agent context includes Shuttle deployment instructions, repo-native guidance if present, and shard spec.
- Agent receives only shard workspace tools.
- Agent transcript events are written to raw logs and indexed.
- Agent can transition shard to `needs_input` or `integrating` through lifecycle tools.
- Tests use a mock LLM/provider and fake tools.

**Dependencies:** SHUT-050, SHUT-051.

### Ticket SHUT-053: Implement Request-Finish Flow

**Outcome:** UI/API can ask a running shard to finish without bypassing agent or integration gates.

**Acceptance Criteria:**

- Request-finish appends a system instruction to the shard agent.
- Request-finish does not set shard state to `integrating`.
- Shard enters `integrating` only after valid `finish_shard`.
- Tests cover request-finish on running, non-running, and already finished shards.

**Dependencies:** SHUT-052.

## Epic E6: Integration, Conflicts, And Push

### Ticket SHUT-060: Enforce Minimum Integration Gate

**Outcome:** Shards cannot merge unless the v1 safety gate passes.

**Acceptance Criteria:**

- Completion report is required.
- Validation command statuses are required.
- Worktree must have no unstaged changes.
- Untracked files are rejected unless every untracked path is listed in completion report.
- Shard branch must be mergeable into `shuttle-main`.
- Repository state must be `open`.
- Tests cover each rejection reason and a passing gate.

**Dependencies:** SHUT-051, SHUT-032.

### Ticket SHUT-061: Squash Merge Finished Shards

**Outcome:** Finished shards are squash-merged into `shuttle-main`.

**Acceptance Criteria:**

- Only one integration runs at a time.
- Squash commit message is generated from completion report.
- Successful merge moves shard to `done`.
- Done shard gets `retainedUntil`.
- Tests cover commit message generation, state transition, and integration lock.

**Dependencies:** SHUT-060, SHUT-021.

### Ticket SHUT-062: Create Conflict Records

**Outcome:** Merge and refresh conflicts create visible conflict records and block integration.

**Acceptance Criteria:**

- Shard merge conflict creates conflict record.
- Upstream refresh conflict creates conflict record.
- Repository state becomes `blocked`.
- Running shards continue.
- New integrations are refused while blocked.
- Tests cover conflict creation and blocked behavior.

**Dependencies:** SHUT-033, SHUT-061.

### Ticket SHUT-063: Resolve Conflict Records Manually

**Outcome:** Operators can mark conflicts resolved after manually correcting `shuttle-main`.

**Acceptance Criteria:**

- Resolution requires repository validation.
- `shuttle-main` must be clean.
- No active git merge state may remain.
- All open conflict records must be resolved before repository returns to `open`.
- Tests cover invalid resolution, partial resolution, and successful unblock.

**Dependencies:** SHUT-062.

### Ticket SHUT-064: Implement Manual Push Actions

**Outcome:** Authenticated API clients can explicitly push `shuttle-main` or retained shard branches to configured targets.

**Acceptance Criteria:**

- Push target must be configured.
- Push action requires idempotency key.
- Shuttle warns but does not block when repo is blocked or risky.
- Push action records audit event with target, ref, actor, warning state, and result.
- Tests cover successful push, unconfigured target rejection, duplicate idempotency replay, and warning metadata.

**Dependencies:** SHUT-023, SHUT-030, SHUT-022.

## Epic E7: REST API

### Ticket SHUT-070: Implement Status And Config APIs

**Outcome:** Clients can inspect server, subsystem, repo, and redacted config state.

**Acceptance Criteria:**

- `GET /api/status` returns server state, repo integration state, and subsystem health.
- `GET /api/config` returns effective config with secrets redacted.
- Responses use stable Codable models in a shared module or server API model namespace.
- Tests cover healthy, fatal startup fixture, and redacted config.

**Dependencies:** SHUT-002, SHUT-010, SHUT-011, SHUT-021.

### Ticket SHUT-071: Implement Shard APIs

**Outcome:** Clients can create, list, inspect, request-finish, answer, and abandon shards.

**Acceptance Criteria:**

- `POST /api/shards` creates shard with idempotency key.
- `GET /api/shards` lists shards with status filters.
- `GET /api/shards/{id}` returns shard detail.
- `POST /api/shards/{id}/request-finish` requests finish.
- `POST /api/shards/{id}/answer` resumes `needs_input`.
- `POST /api/shards/{id}/abandon` abandons eligible shards.
- Tests cover happy paths, invalid transitions, and idempotent create.

**Dependencies:** SHUT-023, SHUT-052, SHUT-053.

### Ticket SHUT-072: Implement Logs And Events APIs

**Outcome:** Clients can page through lifecycle events and raw log indexes.

**Acceptance Criteria:**

- `GET /api/shards/{id}/events` supports cursor pagination.
- `GET /api/shards/{id}/logs` supports cursor pagination over indexed raw log chunks.
- `GET /api/events` supports repo-level event pagination.
- Tests cover pagination, missing shard, and append-only ordering.

**Dependencies:** SHUT-022, SHUT-043.

### Ticket SHUT-073: Implement Conflict, Refresh, And Push APIs

**Outcome:** Clients can inspect conflicts, resolve conflicts, refresh upstream, and push refs.

**Acceptance Criteria:**

- `GET /api/conflicts` lists open and resolved conflict records.
- `POST /api/conflicts/{id}/resolve` resolves after repository validation.
- `POST /api/repository/refresh` starts manual upstream refresh when allowed.
- `POST /api/pushes` performs idempotent push action.
- Tests cover conflict resolution, refresh blocking, push idempotency, and push audit records.

**Dependencies:** SHUT-033, SHUT-063, SHUT-064.

## Epic E8: Operator UI

### Ticket SHUT-080: Build Integration Queue UI

**Outcome:** Browser UI shows the operational queue as the first screen.

**Acceptance Criteria:**

- UI shows server state and subsystem health summary.
- UI shows repo integration state and open conflicts.
- UI groups shards by running, needs input, integrating, and recently completed.
- UI shows recent refresh and push events.
- UI polls REST endpoints; no streaming.
- Playwright or equivalent UI test verifies the queue renders from fixture API data.

**Dependencies:** SHUT-070, SHUT-071, SHUT-073.

### Ticket SHUT-081: Build Shard Detail UI

**Outcome:** Operators can inspect and act on a shard.

**Acceptance Criteria:**

- Detail page shows status, spec, git summary, completion report, retained worktree status, and logs.
- Running shards show request-finish and abandon actions.
- `needs_input` shards show answer form.
- Actions call REST APIs and refresh visible state.
- UI test verifies request-finish, answer, and abandon flows with fixture API data.

**Dependencies:** SHUT-071, SHUT-072.

### Ticket SHUT-082: Build Push And Conflict UI

**Outcome:** Operators can inspect conflicts and perform manual push actions.

**Acceptance Criteria:**

- Conflict panel shows open conflict records and resolution action.
- Push panel shows configured push targets.
- Push action displays warnings before submission.
- Push action uses idempotency key.
- UI test verifies blocked repo display and push warning flow.

**Dependencies:** SHUT-073.

## Epic E9: Recovery, Cleanup, And Limits

### Ticket SHUT-090: Implement Startup Reconciliation

**Outcome:** Shuttle reconciles SQLite, git refs, worktrees, and containers on restart.

**Acceptance Criteria:**

- Missing retained worktrees are logged without corrupting done shards.
- Running shards become resumable if worktree exists.
- Containers are recreated when needed.
- Integrating shards are inspected and resolved to done, running, needs_input, or failed with an event.
- Blocked repo state is reconstructed from open conflict records and git merge state.
- Tests cover each recovery path using fixture repositories and fake Docker.

**Dependencies:** SHUT-021, SHUT-030, SHUT-041, SHUT-062.

### Ticket SHUT-091: Enforce Concurrency Limits

**Outcome:** Configured limits prevent resource exhaustion.

**Acceptance Criteria:**

- Maximum running shards is enforced.
- Maximum queued shards is enforced.
- Integration concurrency remains exactly one.
- Upstream refresh and shard integration cannot mutate `shuttle-main` concurrently.
- Tests cover limit rejection and lock behavior.

**Dependencies:** SHUT-021, SHUT-061.

### Ticket SHUT-092: Implement Retention Cleanup

**Outcome:** Shuttle cleans retained worktrees and raw logs according to config.

**Acceptance Criteria:**

- Done shard worktrees are removed after retention window.
- Local shard branches are removed after retention window when safe.
- Metadata and lifecycle events remain.
- Raw logs rotate or expire according to config.
- Tests cover worktree cleanup, branch cleanup, and raw log cleanup.

**Dependencies:** SHUT-043, SHUT-061.

## Epic E10: Hardening And Release Readiness

### Ticket SHUT-100: Add End-To-End Local Fixture Scenario

**Outcome:** A single test or script exercises the core v1 flow against a local fixture repo.

**Acceptance Criteria:**

- Fixture initializes Shuttle with local repo and fake or controlled agent provider.
- Scenario creates shard, runs command, records completion report, integrates via squash merge, and lists done shard.
- Scenario creates a conflict and verifies repository blocks integration.
- Scenario performs a manual push to a local remote.

**Dependencies:** SHUT-071, SHUT-073, SHUT-090.

### Ticket SHUT-101: Document Operations

**Outcome:** Operators can deploy and run Shuttle v1 without reading source code.

**Acceptance Criteria:**

- README explains v1 scope and non-goals.
- Deployment doc explains volumes, Docker socket, SSH key secrets, and YAML config.
- Operations doc explains shard lifecycle, conflict records, push actions, cleanup, and recovery.
- Example YAML config is included with safe defaults.

**Dependencies:** SHUT-003, SHUT-010, SHUT-092.

### Ticket SHUT-102: Run Verification Suite

**Outcome:** V1 backlog implementation has a final verification gate.

**Acceptance Criteria:**

- `swift build` passes.
- `swift test` passes.
- Docker image builds.
- Local fixture scenario passes.
- UI smoke tests pass.
- Release notes list known v1 limitations.

**Dependencies:** SHUT-100, SHUT-101.

## Cross-Epic Dependency Order

1. E0 Project Foundation.
2. E1 Configuration And Secrets.
3. E2 Persistence And Domain State.
4. E3 Git Repository Core.
5. E4 Containers, Scoped Execution, And Logs.
6. E5 Shard Workspace Tools And Agent Runtime.
7. E6 Integration, Conflicts, And Push.
8. E7 REST API.
9. E8 Operator UI.
10. E9 Recovery, Cleanup, And Limits.
11. E10 Hardening And Release Readiness.

## Backlog Self-Review

- Covers v1 scope: one repo, REST/UI, scoped execution, manual conflicts, manual push.
- Covers v1 non-goals by excluding management workspace tooling, streaming, fine-grained auth, auto-conflict agents, distributed workers, and Shuttle-owned CI.
- Preserves safety invariants through dedicated tickets for tool scoping, Docker command execution, integration gate, idempotency, and recovery.
- Keeps implementation dependency order explicit enough to convert individual tickets into task-level plans.
