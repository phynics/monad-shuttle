# SHUT-031 Branch Naming Contract Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Define a stable, human-readable branch naming contract for shards that preserves immutable shard identity and handles collisions deterministically.

**Architecture:** Add a pure naming utility under `Sources/ShuttleServer/Git` that derives a branch slug from title or spec summary, appends a stable suffix from immutable shard ID, and extends that suffix on collisions. Keep the scope limited to naming; no repository or worktree mutation in this ticket.

**Tech Stack:** Swift 6, Foundation string processing, XCTest

---

### Task 1: Add Naming Tests First

**Files:**
- Create: `Tests/ShuttleServerTests/ShuttleBranchNamerTests.swift`

- [ ] **Step 1: Write failing tests**

Coverage:
- normal title slug
- fallback to spec summary
- unsafe character sanitization
- long title truncation
- collision handling by suffix extension

- [ ] **Step 2: Run focused tests**

Run: `swift test --filter ShuttleBranchNamerTests`
Expected: FAIL until naming utility exists.

### Task 2: Implement Pure Branch Naming Utility

**Files:**
- Create: `Sources/ShuttleServer/Git/ShuttleBranchNamer.swift`

- [ ] **Step 1: Add stable branch format**

Format:
- prefix: `shuttle/shards/`
- slug from title or first spec line
- suffix from normalized shard ID

- [ ] **Step 2: Add sanitization and collision handling**

Rules:
- lowercase
- replace unsafe characters with `-`
- collapse repeated `-`
- trim leading/trailing `-`
- truncate slug to fixed max length
- extend suffix by fixed increments until unique

### Task 3: Verify And Commit

**Files:**
- Create: `docs/superpowers/plans/2026-06-05-shut-031-branch-naming-contract.md`

- [ ] **Step 1: Run focused tests**

Run: `swift test --filter ShuttleBranchNamerTests`
Expected: PASS.

- [ ] **Step 2: Run package verification**

Run: `swift test`
Expected: PASS.

Run: `swift build`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add Sources/ShuttleServer/Git/ShuttleBranchNamer.swift Tests/ShuttleServerTests/ShuttleBranchNamerTests.swift docs/superpowers/plans/2026-06-05-shut-031-branch-naming-contract.md
git commit -m "feat: add Shuttle branch naming contract"
```

## Self-Review

- Spec coverage: title/spec derivation, stable suffix, immutable ID separation, and collision behavior are all encoded.
- Placeholder scan: no TODO placeholders.
- Type consistency: branch names remain strings while shard IDs stay independent for future API and DB wiring.
