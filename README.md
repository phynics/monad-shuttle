# Shuttle

Shuttle is an experimental coding environment for managing one repository as a Docker-deployable workspace system.

It is intended to:

- maintain a bare managed repository
- fork an integration branch as local `shuttle-main`
- create one worktree per shard
- run shard tooling and agent activity against isolated shard workspaces
- integrate completed shard work back into `shuttle-main`

## Status

This repository is an experiment in building a fully AI-coded project under human direction.

It is not production-ready. The current codebase covers the early v1 foundation:

- Swift package and server bootstrap
- Docker deployment skeleton
- YAML config loading and validation
- SQLite schema and stores
- repository bootstrap and worktree creation
- shard container and command execution plumbing
- shard workspace file, git, and lifecycle tools

Work is still ongoing. The next major step after the current state is the in-process PositronicKit agent runner.

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
  [docs/superpowers/specs/2026-05-28-shuttle-design.md](docs/superpowers/specs/2026-05-28-shuttle-design.md)
- V1 epics and tickets:
  [docs/superpowers/plans/2026-05-28-shuttle-v1-epics-tickets.md](docs/superpowers/plans/2026-05-28-shuttle-v1-epics-tickets.md)
- Ticket implementation notes:
  [docs/superpowers/plans](docs/superpowers/plans)

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

## Repository Layout

```text
Sources/
  ShuttleServer/
  ShuttleWebUI/
Tests/
  ShuttleServerTests/
  ShuttleWebUITests/
docs/
  deployment.md
  superpowers/specs/
  superpowers/plans/
deploy/
  config/
  env/
```

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
- [deploy/config/shuttle.example.yaml](deploy/config/shuttle.example.yaml)

## License

MIT. See [LICENSE](LICENSE).
