# SHUT-050 Shard Workspace File And Git Tools Implementation Plan

**Goal:** Expose PositronicKit-compatible shard workspace tools that operate only inside the shard worktree.

**Architecture:** Reuse PKShared jailed filesystem tools for read/list/find/search. Add Shuttle-specific write/delete tools backed by `PathSanitizer` with the shard worktree as both current directory and jail root. Add Shuttle-specific git tools that run through `ShuttleShardCommandExecutionService`, which means git commands execute via Docker in the configured container workdir.

### Tasks

- [ ] Add tests proving reused file tools reject traversal, absolute outside paths, and symlink escapes.
- [ ] Add tests for scoped write/delete operations.
- [ ] Add tests that git tools execute through Docker command execution in the configured workdir.
- [ ] Implement `ShuttleWriteFileTool`, `ShuttleDeleteFileTool`, git tools, and a factory that returns PositronicKit-compatible `AnyTool` values.
- [ ] Verify with focused tests, full `swift test`, and `swift build`.
