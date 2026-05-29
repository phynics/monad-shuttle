# SHUT-023 Idempotency Records Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add idempotency record handling that supports safe replay for duplicate shard/push requests and conflict errors for mismatched replays.

**Architecture:** Introduce a small GRDB-backed idempotency store around the existing `idempotency_keys` table. The store provides an atomic `recordOrReplay` API keyed by `(idempotency_key, scope)` semantics and enforces request-hash consistency.

**Tech Stack:** Swift 6, GRDB, SQLite, XCTest

---

### Task 1: Add Idempotency Tests First

**Files:**
- Create: `Tests/ShuttleServerTests/ShuttleIdempotencyStoreTests.swift`

- [ ] **Step 1: Write failing tests**

Coverage:
- stores new idempotency record
- replays existing record for same key+scope+request hash
- returns conflict for same key+scope with different request hash

- [ ] **Step 2: Run focused tests**

Run: `swift test --filter ShuttleIdempotencyStoreTests`
Expected: FAIL until store implementation exists.

### Task 2: Implement Idempotency Store

**Files:**
- Create: `Sources/ShuttleServer/Database/ShuttleIdempotencyStore.swift`

- [ ] **Step 1: Add core types**

Types:
- `ShuttleIdempotencyRecord`
- `ShuttleIdempotencyStoreResult` (`recorded` / `replayed`)
- `ShuttleIdempotencyStoreError` (`requestMismatch`)

- [ ] **Step 2: Add atomic `recordOrReplay` API**

Method:

```swift
recordOrReplay(
  key: String,
  scope: String,
  requestHash: String,
  responseJSON: String,
  createdAt: Date,
  expiresAt: Date?
)
```

Behavior:
- no record: insert and return `.recorded`
- same key+scope+request hash: return `.replayed(existing)`
- same key+scope with different request hash: throw `.requestMismatch`

### Task 3: Verify And Commit

**Files:**
- Create: `docs/superpowers/plans/2026-05-29-shut-023-idempotency-records.md`

- [ ] **Step 1: Run focused tests**

Run: `swift test --filter ShuttleIdempotencyStoreTests`
Expected: PASS.

- [ ] **Step 2: Run package verification**

Run: `swift test`
Expected: PASS.

Run: `swift build`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add Sources/ShuttleServer/Database/ShuttleIdempotencyStore.swift Tests/ShuttleServerTests/ShuttleIdempotencyStoreTests.swift docs/superpowers/plans/2026-05-29-shut-023-idempotency-records.md
git commit -m "feat: add Shuttle idempotency store"
```

## Self-Review

- Spec coverage: replay and mismatch behavior aligns with SHUT-023 acceptance criteria.
- Placeholder scan: no TODO placeholders.
- Type consistency: key/scope/request-hash contract is explicit for upcoming shard/push API handlers.
