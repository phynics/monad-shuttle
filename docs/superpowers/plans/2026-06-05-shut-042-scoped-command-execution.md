# SHUT-042 Scoped Command Execution Implementation Plan

**Goal:** Run shard commands only through `docker exec` in the shard container workdir, enforce command policy, and log command results with timing.

**Architecture:** Extend the Docker client with typed `exec` requests/results. Add a command execution service that loads shard container metadata, applies policy, routes execution through the Docker access controller, and appends command logs to the log volume with index rows in SQLite.

### Tasks

- [ ] Add focused tests for workdir scoping, policy rejection, and command logging.
- [ ] Extend the Docker client and access controller with `exec` support.
- [ ] Add a command log store writing append-only per-shard command logs with `log_indexes` rows.
- [ ] Add a shard command execution service for general and named commands.
- [ ] Verify with `swift test --filter ShuttleShardCommandExecutionServiceTests`, `swift test`, and `swift build`.
