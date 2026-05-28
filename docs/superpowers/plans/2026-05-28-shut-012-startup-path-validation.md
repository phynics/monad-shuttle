# SHUT-012 Startup Path Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Validate required deployment paths and SSH key readability at startup before serving work.

**Architecture:** Extend the loaded YAML config with a `paths` section for database/git/worktrees/logs mounts, defaulting to the Docker volume locations. During environment creation, validate those volume directories plus config and secrets parent directories and the SSH key file itself, then surface precise subsystem failures in status.

**Tech Stack:** Swift 6, XCTest, Hummingbird status store

---

### Task 1: Add Startup Validation Tests

**Files:**
- Create: `Tests/ShuttleServerTests/ShuttleStartupValidationTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
func testStartupValidationPassesWhenAllRequiredPathsExist() async throws
func testStartupValidationFailsForMissingDatabaseVolumePath() async throws
func testStartupValidationFailsForMissingSSHKeyPath() async throws
```

- [ ] **Step 2: Run focused tests to verify failure**

Run: `swift test --filter ShuttleStartupValidationTests`
Expected: FAIL because startup path validation is not implemented yet.

### Task 2: Extend Config Model And Loader For Paths

**Files:**
- Modify: `Sources/ShuttleServer/Config/ShuttleConfig.swift`
- Modify: `Sources/ShuttleServer/Config/ShuttleConfigLoader.swift`
- Modify: `Sources/ShuttleServer/HTTP/ShuttleConfigResponse.swift`
- Modify: `Tests/ShuttleServerTests/ShuttleConfigLoaderTests.swift`
- Modify: `Tests/ShuttleServerTests/ShuttleConfigRedactionTests.swift`
- Modify: `deploy/config/shuttle.example.yaml`

- [ ] **Step 1: Add typed `paths` model**

```swift
struct Paths {
    let databasePath: String
    let gitPath: String
    let worktreesPath: String
    let logsPath: String
}
```

- [ ] **Step 2: Parse and validate `paths` in loader**

```swift
paths:
  database: /data/db
  git: /data/git
  worktrees: /data/worktrees
  logs: /data/logs
```

- [ ] **Step 3: Keep API response in sync**

Expose `paths` in `ShuttleConfigResponse`.

### Task 3: Add Startup Validation Logic

**Files:**
- Modify: `Sources/ShuttleServer/ShuttleServerApp.swift`
- Modify: `Sources/ShuttleServer/Runtime/ShuttleServerConfiguration.swift`

- [ ] **Step 1: Validate required paths during `makeEnvironment`**

Checks:
- database path exists and is a directory
- git path exists and is a directory
- worktrees path exists and is a directory
- logs path exists and is a directory
- config volume path exists (`dirname(configPath)`)
- secrets volume path exists (`dirname(ssh_key_path)`)
- SSH key path exists and is readable

- [ ] **Step 2: Set `fatal` and precise subsystem health on failure**

Use subsystem mapping:
- `database` for database path failures
- `git` for git path failures
- `volumes` for worktrees/logs path failures
- `config` for config/secrets/SSH key failures

- [ ] **Step 3: Run tests**

Run: `swift test --filter ShuttleStartupValidationTests`
Expected: PASS.

Run: `swift test`
Expected: PASS.

Run: `swift build`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Sources/ShuttleServer/Config/ShuttleConfig.swift Sources/ShuttleServer/Config/ShuttleConfigLoader.swift Sources/ShuttleServer/HTTP/ShuttleConfigResponse.swift Sources/ShuttleServer/ShuttleServerApp.swift Sources/ShuttleServer/Runtime/ShuttleServerConfiguration.swift Tests/ShuttleServerTests/ShuttleStartupValidationTests.swift Tests/ShuttleServerTests/ShuttleConfigLoaderTests.swift Tests/ShuttleServerTests/ShuttleConfigRedactionTests.swift deploy/config/shuttle.example.yaml docs/superpowers/plans/2026-05-28-shut-012-startup-path-validation.md
git commit -m "feat: validate startup paths and ssh key access"
```

## Self-Review

- Spec coverage: validates all required startup path categories and SSH key readability.
- Placeholder scan: no TODO placeholders remain.
- Type consistency: `paths` names are consistent across YAML, model, loader, tests, and API response.
