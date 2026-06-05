# SHUT-043 Raw Log Storage And Rotation Implementation Plan

**Goal:** Store raw command logs outside SQLite, keep index metadata in `log_indexes`, rotate logs when a shard log file exceeds the configured size limit, and delete expired raw logs according to retention.

**Architecture:** Extend the existing command log store instead of creating a second log subsystem. Keep JSONL raw logs on disk, keep only references and offsets in SQLite, and add a cleanup path that removes expired index rows and deletes orphaned raw log files.

### Tasks

- [ ] Add focused tests for raw log writes, max-size rotation, retention cleanup, and index consistency.
- [ ] Extend `ShuttleCommandLogStore` with size-aware file selection and retention cleanup.
- [ ] Wire the updated store constructor through the shard command execution service tests.
- [ ] Verify with `swift test --filter ShuttleCommandLogStoreTests`, `swift test`, and `swift build`.
