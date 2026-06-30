# Shuttle

Shuttle is an experimental coding environment for managing one repository as a Docker-deployable shard workspace system.

It is intended to:

- maintain a bare managed repository
- fork an integration branch as local `shuttle-main`
- create one worktree per shard
- run shard tooling and agent activity against isolated shard workspaces
- integrate completed shard work back into `shuttle-main`

## Status

This repository is an experiment in building a fully AI-coded project under human direction.

It is not production-ready. The current codebase now covers the Shuttle v1 backlog through hardening work, including:

- Swift package and server bootstrap
- Docker deployment skeleton
- YAML config loading, validation, and redaction
- SQLite schema and stores
- repository bootstrap, `shuttle-main`, and worktree creation
- per-shard container and scoped command execution plumbing
- shard workspace file, git, and lifecycle tools
- shard agent runner integration with PositronicKit
- integration gate, squash merge, conflict handling, refresh, and push controls
- REST APIs and operator UI
- startup reconciliation, retention cleanup, concurrency limits, and end-to-end fixture coverage

## Project Context

Shuttle is being developed alongside:

- [monad-project](https://github.com/phynics/monad-project)
- [PositronicKit](https://github.com/phynics/PositronicKit)

Today, Shuttle depends on a sibling checkout of `PositronicKit` through a local SwiftPM path dependency:

```swift
.package(path: "../PositronicKit")
```

That means the expected local layout is:

```text
monad-project/
  Monad/
  PositronicKit/
  Shuttle/
```

## V1 Scope

Shuttle v1 covers:

- one repository per Shuttle server
- REST APIs and a local/admin operator UI
- scoped shard execution in per-worktree containers
- manual conflict handling
- manual push actions to configured targets

## V1 Non-Goals

Shuttle v1 does not attempt:

- multi-repository management
- PositronicKit management workspaces
- distributed workers
- auto-running conflict-resolution shards
- fine-grained auth
- Shuttle-owned CI
- automatic pushes

## Experiment Framing

This repository is intentionally documenting the process, not just the output.

The working model so far has been:

1. write the product/design spec first
2. cut scope aggressively for v1
3. split the work into epics and tickets
4. implement ticket-by-ticket
5. keep tests close to each ticket
6. review larger changes before moving on

The implementation has been human-directed and AI-executed. The repo history reflects that flow directly.

## Workflow So Far

The project was not started by writing code first. The current implementation follows a documented chain:

- Design spec:
  [../workflow/Shuttle/specs/2026-05-28-shuttle-design.md](../workflow/Shuttle/specs/2026-05-28-shuttle-design.md)
- V1 epics and tickets:
  [../workflow/Shuttle/plans/2026-05-28-shuttle-v1-epics-tickets.md](../workflow/Shuttle/plans/2026-05-28-shuttle-v1-epics-tickets.md)
- Ticket implementation notes:
  [../workflow/Shuttle/plans](../workflow/Shuttle/plans)

Implemented tickets so far include:

- `SHUT-001` package skeleton
- `SHUT-002` server entrypoint and health route
- `SHUT-003` Docker skeleton
- `SHUT-010` config model
- `SHUT-011` redacted config projection
- `SHUT-012` startup path validation
- `SHUT-020` SQLite migrations
- `SHUT-021` state machine
- `SHUT-022` audit events
- `SHUT-023` idempotency records
- `SHUT-030` bare repository bootstrap
- `SHUT-031` branch naming
- `SHUT-032` worktree creation and retention metadata
- `SHUT-040` Docker access validation
- `SHUT-041` per-shard containers
- `SHUT-042` scoped command execution
- `SHUT-043` raw log rotation
- `SHUT-050` shard workspace file and git tools
- `SHUT-051` shard lifecycle tools
- `SHUT-052` shard runner
- `SHUT-053` finish-request flow
- `SHUT-060` integration gate
- `SHUT-061` squash merge
- `SHUT-062` conflict records
- `SHUT-063` manual conflict resolution
- `SHUT-064` manual push actions
- `SHUT-070` status and config APIs
- `SHUT-071` shard APIs
- `SHUT-072` logs and events APIs
- `SHUT-073` conflict, refresh, and push APIs
- `SHUT-080` queue UI
- `SHUT-081` shard detail UI
- `SHUT-082` push and conflict UI
- `SHUT-090` startup reconciliation
- `SHUT-091` concurrency limits
- `SHUT-092` retention cleanup
- `SHUT-100` end-to-end local fixture scenario

## Repository Layout

```text
Sources/
  ShuttleServer/
  ShuttleWebUI/
Tests/
  ShuttleServerTests/
  ShuttleWebUITests/
docs/                  # reference docs only
  deployment.md
  operations.md
deploy/
  config/
  env/
```

Workflow artifacts (design spec, ticket-by-ticket plans) live centrally at the
workspace root, **not** in this repo's `docs/`:

```text
../workflow/Shuttle/
  specs/   # design spec
  plans/   # SHUT-NNN implementation plans
```

See the root `../CLAUDE.md` for the full cross-project layout.

## Build And Test

From the repository root:

```bash
swift test
swift build
```

The current package targets are:

- `ShuttleServer`
- `ShuttleWebUI`

## Deployment Artifacts

The repository already contains:

- [Dockerfile](Dockerfile)
- [compose.yaml](compose.yaml)
- [docs/deployment.md](docs/deployment.md)
- [docs/operations.md](docs/operations.md)
- [docs/release-notes-v1.md](docs/release-notes-v1.md)
- [deploy/config/shuttle.example.yaml](deploy/config/shuttle.example.yaml)

## License

MIT. See [LICENSE](LICENSE).
