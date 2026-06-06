# SHUT-052: Implement PositronicKit Agent Runner

- [x] Add focused runner tests covering prompt assembly, transcript logging, and lifecycle-tool execution.
- [x] Implement a Shuttle shard agent runner that uses `PositronicKitCore` with only shard-scoped tools.
- [x] Build runner context from Shuttle deployment instructions, optional repo `AGENTS.md`, and shard spec.
- [x] Add transcript persistence that writes raw agent events to the log volume and indexes them in SQLite.
- [ ] Wire the runner into shard start/resume API flow in a later ticket.
- [ ] Verify with `swift test --filter ShuttleShardAgentRunnerTests`, `swift test`, and `swift build`.
