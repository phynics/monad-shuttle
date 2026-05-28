# SHUT-010 YAML Config Model Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a strict YAML config loader for Shuttle that validates the v1 schema, rejects unknown fields, and provides deterministic validation errors.

**Architecture:** Keep config loading as a focused parsing layer under `Sources/ShuttleServer/Config`. Parse YAML directly with `Yams`, map it into a typed `ShuttleConfig`, and validate field presence, field types, path rules, limits, and push targets before the rest of the server consumes it.

**Tech Stack:** Swift 6, SwiftPM, Yams, XCTest

---

### Task 1: Lock In Config Loader Behavior With Tests

**Files:**
- Create: `Tests/ShuttleServerTests/ShuttleConfigLoaderTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import XCTest
@testable import ShuttleServer

final class ShuttleConfigLoaderTests: XCTestCase {
    func testLoadValidConfigParsesExpectedFields() throws { /* ... */ }
    func testLoadConfigRejectsMissingRequiredField() throws { /* ... */ }
    func testLoadConfigRejectsUnknownField() throws { /* ... */ }
    func testLoadConfigRejectsInvalidAbsolutePathField() throws { /* ... */ }
    func testLoadConfigRejectsInvalidConcurrencyLimits() throws { /* ... */ }
    func testLoadConfigRejectsInvalidPushTargetDefinition() throws { /* ... */ }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ShuttleConfigLoaderTests`
Expected: FAIL because `ShuttleConfigLoader`, `ShuttleConfig`, and `ShuttleConfigError` do not exist yet.

### Task 2: Implement Typed Config Model And Strict YAML Loader

**Files:**
- Modify: `Package.swift`
- Create: `Sources/ShuttleServer/Config/ShuttleConfig.swift`
- Create: `Sources/ShuttleServer/Config/ShuttleConfigError.swift`
- Create: `Sources/ShuttleServer/Config/ShuttleConfigLoader.swift`

- [ ] **Step 1: Add the YAML dependency and config model**

```swift
.package(url: "https://github.com/jpsim/Yams", "5.4.0"..<"7.0.0")
```

```swift
struct ShuttleConfig: Equatable, Sendable {
    struct Repository: Equatable, Sendable { /* ... */ }
    struct Runtime: Equatable, Sendable { /* ... */ }
    struct Refresh: Equatable, Sendable { /* ... */ }
    struct Retention: Equatable, Sendable { /* ... */ }
    struct Limits: Equatable, Sendable { /* ... */ }
    struct PushTarget: Equatable, Sendable { /* ... */ }
    struct Auth: Equatable, Sendable { /* ... */ }
    struct Instructions: Equatable, Sendable { /* ... */ }
    struct Server: Equatable, Sendable { /* ... */ }
}
```

- [ ] **Step 2: Add the strict loader and validation errors**

```swift
enum ShuttleConfigError: Error, Equatable, Sendable {
    case unreadableFile(String)
    case invalidYAML(String)
    case missingRequiredField(String)
    case unknownField(String)
    case invalidType(field: String, expected: String)
    case invalidValue(field: String, reason: String)
    case invalidPath(field: String, reason: String)
    case duplicateField(String)
}
```

```swift
enum ShuttleConfigLoader {
    static func load(fromFilePath filePath: String) throws -> ShuttleConfig {
        // Read YAML, require a top-level mapping, validate keys, map into ShuttleConfig.
    }
}
```

- [ ] **Step 3: Run focused config tests**

Run: `swift test --filter ShuttleConfigLoaderTests`
Expected: PASS.

### Task 3: Wire Startup Validation And Update Example Config

**Files:**
- Modify: `Sources/ShuttleServer/ShuttleServerApp.swift`
- Modify: `deploy/config/shuttle.example.yaml`

- [ ] **Step 1: Validate explicit config files during environment creation**

```swift
if let configPath = configuration.configPath {
    loadedConfig = try ShuttleConfigLoader.load(fromFilePath: configPath)
}
```

- [ ] **Step 2: Expand the example YAML to match the schema**

```yaml
refresh:
  schedule: "0 * * * *"

retention:
  worktree_days: 7
  raw_logs_days: 14
  raw_logs_max_bytes: 10485760
```

- [ ] **Step 3: Run package verification**

Run: `swift test`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Package.swift Sources/ShuttleServer/Config Sources/ShuttleServer/ShuttleServerApp.swift Tests/ShuttleServerTests/ShuttleConfigLoaderTests.swift deploy/config/shuttle.example.yaml docs/superpowers/plans/2026-05-28-shut-010-yaml-config-model.md
git commit -m "feat: add Shuttle YAML config model"
```

## Self-Review

- Spec coverage: covers the `SHUT-010` schema, validation, and test requirements.
- Placeholder scan: no implementation TODO markers remain.
- Type consistency: the config field names in tests, loader, and example YAML match the v1 schema.
