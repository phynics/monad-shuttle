# SHUT-030 Bootstrap Bare Repository Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bootstrap Shuttle’s managed bare repository from the configured upstream and ensure local `shuttle-main` exists and remains valid across restarts.

**Architecture:** Add a small git bootstrapper around shell `git` invocations. Keep repository bootstrap deterministic: use one bare repo location under `paths.git`, fetch the configured source branch into a stable remote-tracking ref, then create `shuttle-main` only when absent. Wire this into startup after path validation so git failures mark the `git` subsystem as `fatal`.

**Tech Stack:** Swift 6, Foundation `Process`, local git fixtures, XCTest

---

### Task 1: Add Fixture Git Tests First

**Files:**
- Create: `Tests/ShuttleServerTests/ShuttleGitTestFixture.swift`
- Create: `Tests/ShuttleServerTests/ShuttleRepositoryBootstrapTests.swift`
- Modify: `Tests/ShuttleServerTests/ShuttleStartupValidationTests.swift`

- [ ] **Step 1: Write failing tests**

Coverage:
- fresh bootstrap clones bare repo and creates `shuttle-main`
- rerun fetches updated upstream branch
- rerun rejects origin mismatch
- startup validation tests use a real local fixture repo so they still test path validation

- [ ] **Step 2: Run focused tests**

Run: `swift test --filter ShuttleRepositoryBootstrapTests`
Expected: FAIL until the bootstrapper exists.

### Task 2: Implement Git Bootstrapper And Startup Wiring

**Files:**
- Modify: `.gitignore`
- Create: `Sources/ShuttleServer/Git/ShuttleGitShell.swift`
- Create: `Sources/ShuttleServer/Git/ShuttleRepositoryBootstrapper.swift`
- Modify: `Sources/ShuttleServer/Runtime/ShuttleServerConfiguration.swift`
- Modify: `Sources/ShuttleServer/ShuttleServerApp.swift`

- [ ] **Step 1: Add a minimal git shell wrapper**

```swift
enum ShuttleGitShell {
    static func run(_ arguments: [String], workingDirectory: String? = nil) throws -> ShuttleGitShellResult
}
```

- [ ] **Step 2: Add repository bootstrapper**

Behavior:
- bare repo path is `paths.git/repository.git`
- clone `--bare` on first startup
- validate existing `origin` URL matches config
- fetch `refs/heads/<source>` into `refs/remotes/origin/<source>`
- create `refs/heads/shuttle-main` from fetched upstream when absent
- validate existing `shuttle-main` with `rev-parse` when present

- [ ] **Step 3: Wire bootstrap into `makeEnvironment`**

Rules:
- run after config/path validation
- mark subsystem `git` as failed on bootstrap errors
- set server state `fatal` on git bootstrap failure

### Task 3: Verify And Commit

**Files:**
- Create: `docs/superpowers/plans/2026-06-05-shut-030-bootstrap-bare-repository.md`

- [ ] **Step 1: Run focused tests**

Run: `swift test --filter ShuttleRepositoryBootstrapTests`
Expected: PASS.

- [ ] **Step 2: Run package verification**

Run: `swift test`
Expected: PASS.

Run: `swift build`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add .gitignore Sources/ShuttleServer/Git/ShuttleGitShell.swift Sources/ShuttleServer/Git/ShuttleRepositoryBootstrapper.swift Sources/ShuttleServer/Runtime/ShuttleServerConfiguration.swift Sources/ShuttleServer/ShuttleServerApp.swift Tests/ShuttleServerTests/ShuttleGitTestFixture.swift Tests/ShuttleServerTests/ShuttleRepositoryBootstrapTests.swift Tests/ShuttleServerTests/ShuttleStartupValidationTests.swift docs/superpowers/plans/2026-06-05-shut-030-bootstrap-bare-repository.md
git commit -m "feat: bootstrap Shuttle bare repository"
```

## Self-Review

- Spec coverage: fresh clone, existing repo validation, branch fetch, `shuttle-main` creation, and existing branch validation are all covered.
- Placeholder scan: no TODO placeholders.
- Type consistency: managed bare repo path and branch names are stable for downstream worktree and refresh tickets.
