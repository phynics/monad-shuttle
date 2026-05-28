# SHUT-011 Redact Config And Secrets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose effective Shuttle config through the API without leaking secret material or raw parser output.

**Architecture:** Add a dedicated API-facing config projection that is separate from the internal typed config model. Keep the redaction policy narrow and explicit for v1: redact SSH key paths in API payloads and avoid surfacing raw YAML parser text in validation errors.

**Tech Stack:** Swift 6, Hummingbird, XCTest

---

### Task 1: Lock Redaction Behavior With Tests

**Files:**
- Create: `Tests/ShuttleServerTests/ShuttleConfigRedactionTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
final class ShuttleConfigRedactionTests: XCTestCase {
    func testRedactedConfigMasksSSHKeyPath() { /* ... */ }
    func testInvalidYAMLDoesNotExposeRawSecretLookingContent() throws { /* ... */ }
    func testConfigEndpointReturnsRedactedEffectiveConfig() async throws { /* ... */ }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ShuttleConfigRedactionTests`
Expected: FAIL because the redacted config response model and `/api/config` route do not exist yet.

### Task 2: Add Redacted Config API Model And Route

**Files:**
- Create: `Sources/ShuttleServer/HTTP/ShuttleConfigResponse.swift`
- Modify: `Sources/ShuttleServer/HTTP/ShuttleServerRoutes.swift`
- Modify: `Sources/ShuttleServer/ShuttleServerApp.swift`

- [ ] **Step 1: Add the API-facing redacted config model**

```swift
public struct ShuttleConfigResponse: ResponseCodable, Equatable, Sendable {
    public let repository: Repository
    public let runtime: Runtime
    // ...

    init(redacting config: ShuttleConfig) {
        self.repository = .init(
            url: config.repository.url,
            sourceBranch: config.repository.sourceBranch,
            sshKeyPath: "<redacted>"
        )
        // ...
    }
}
```

- [ ] **Step 2: Add the config route**

```swift
router.get("/api/config") { _, _ in
    guard let loadedConfig else {
        throw HTTPError(.notFound)
    }
    return ShuttleConfigResponse(redacting: loadedConfig)
}
```

- [ ] **Step 3: Run focused redaction tests**

Run: `swift test --filter ShuttleConfigRedactionTests`
Expected: PASS.

### Task 3: Harden Loader Error Redaction And Verify Package

**Files:**
- Modify: `Sources/ShuttleServer/Config/ShuttleConfigLoader.swift`

- [ ] **Step 1: Replace raw YAML parser detail with a generic validation error**

```swift
catch {
    throw ShuttleConfigError.invalidYAML("invalid YAML document")
}
```

- [ ] **Step 2: Run package verification**

Run: `swift test`
Expected: PASS.

Run: `swift build`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add Sources/ShuttleServer/HTTP/ShuttleConfigResponse.swift Sources/ShuttleServer/HTTP/ShuttleServerRoutes.swift Sources/ShuttleServer/ShuttleServerApp.swift Sources/ShuttleServer/Config/ShuttleConfigLoader.swift Tests/ShuttleServerTests/ShuttleConfigRedactionTests.swift docs/superpowers/plans/2026-05-28-shut-011-redact-config-and-secrets.md
git commit -m "feat: redact Shuttle config responses"
```

## Self-Review

- Spec coverage: covers the `SHUT-011` API redaction and validation-error redaction requirements.
- Placeholder scan: no placeholders remain.
- Type consistency: the API response fields mirror the current config schema and only redact the intended secret field.
