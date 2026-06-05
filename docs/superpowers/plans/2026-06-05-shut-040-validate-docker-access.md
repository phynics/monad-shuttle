# SHUT-040 Validate Docker Access Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a fakeable Docker access boundary that reports Docker socket health in subsystem status and blocks container-dependent operations with structured errors when Docker is unavailable.

**Architecture:** Introduce a `Docker` source area with a small probe client and an access controller actor. Wire startup environment creation through that controller so the `docker` subsystem becomes real instead of hard-coded. Keep actual container lifecycle out of scope for this ticket.

**Tech Stack:** Swift 6, Foundation, XCTest

---

### Task 1: Add Docker Access Tests First

**Files:**
- Create: `Tests/ShuttleServerTests/ShuttleDockerAccessTests.swift`

- [ ] **Step 1: Write failing tests**

Coverage:
- healthy probe marks `docker` subsystem `ok`
- failed probe marks `docker` subsystem `failed` without making server fatal
- container-dependent guarded operations throw structured errors when Docker is unavailable
- startup environment uses an injected fake Docker client

- [ ] **Step 2: Run focused tests**

Run: `swift test --filter ShuttleDockerAccessTests`
Expected: FAIL until Docker access boundary exists.

### Task 2: Add Docker Access Boundary

**Files:**
- Create: `Sources/ShuttleServer/Docker/ShuttleDockerClient.swift`
- Create: `Sources/ShuttleServer/Docker/ShuttleDockerAccessController.swift`
- Update: `Sources/ShuttleServer/ShuttleServerApp.swift`

- [ ] **Step 1: Add fakeable health probe client**

Rules:
- live probe checks mounted Docker socket path
- fake probes can be injected directly in tests

- [ ] **Step 2: Add guarded access controller**

Rules:
- controller updates `docker` subsystem health
- container-dependent operations call a single guarded entrypoint
- unavailable Docker throws structured errors

- [ ] **Step 3: Wire startup health through environment creation**

Rules:
- environment boot probes Docker health
- Docker failure is non-fatal
- subsystem detail is preserved for `/api/status`

### Task 3: Verify And Commit

**Files:**
- Create: `docs/superpowers/plans/2026-06-05-shut-040-validate-docker-access.md`

- [ ] **Step 1: Run focused tests**

Run: `swift test --filter ShuttleDockerAccessTests`
Expected: PASS.

- [ ] **Step 2: Run package verification**

Run: `swift test`
Expected: PASS.

Run: `swift build`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add Sources/ShuttleServer/Docker/ShuttleDockerClient.swift Sources/ShuttleServer/Docker/ShuttleDockerAccessController.swift Sources/ShuttleServer/ShuttleServerApp.swift Tests/ShuttleServerTests/ShuttleDockerAccessTests.swift docs/superpowers/plans/2026-06-05-shut-040-validate-docker-access.md
git commit -m "feat: validate Shuttle Docker access"
```

## Self-Review

- Spec coverage: Docker health, subsystem reporting, and structured refusal of container operations are all enforced directly in tests.
- Placeholder scan: no TODO placeholders.
- Scope control: this ticket deliberately stops at health and guarded access; container creation waits for `SHUT-041`.
