# SHUT-051 Shard Lifecycle Tools Implementation Plan

**Goal:** Expose explicit shard lifecycle tools for finish, input requests, and abandon, backed by durable state and audit records.

**Architecture:** Add a lifecycle service that validates shard-state transitions through the existing state machine, persists structured completion reports, updates shard state in SQLite, and records append-only audit events. Expose thin PositronicKit-compatible tools that delegate to the service. Extend the shard workspace tool factory so callers can include lifecycle tools in the same workspace surface.

### Tasks

- [x] Add focused tests for valid and invalid `finish_shard` reports.
- [x] Add focused tests for `request_input` and `abandon_shard`.
- [x] Add durable completion-report persistence and shard state update support.
- [x] Add lifecycle audit event coverage for input requests.
- [x] Implement lifecycle service and PositronicKit-compatible shard lifecycle tools.
- [x] Verify with focused lifecycle tests, full `swift test`, and `swift build`.
