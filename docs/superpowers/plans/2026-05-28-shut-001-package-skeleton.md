# SHUT-001 Package Skeleton Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the initial Shuttle Swift package so `swift build` and `swift test` succeed with a minimal server executable, a separate UI target, and smoke tests.

**Architecture:** This ticket only bootstraps the package and test harness. It adds an executable server target, a separate UI target, a path dependency on `../PositronicKit`, and minimal bootstrap types that smoke tests can import and validate. No HTTP, config, or runtime logic is added in this ticket.

**Tech Stack:** Swift 6, SwiftPM, XCTest, local path dependency on `../PositronicKit`

---

### Task 1: Bootstrap Manifest And Test Harness

**Files:**
- Create: `Package.swift`
- Create: `Tests/ShuttleServerTests/ShuttleServerSmokeTests.swift`
- Create: `Tests/ShuttleWebUITests/ShuttleWebUISmokeTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import ShuttleServer

final class ShuttleServerSmokeTests: XCTestCase {
    func testStartupBannerMentionsTargetName() {
        XCTAssertEqual(ShuttleServerApp.makeStartupBanner(), "ShuttleServer bootstrap ready")
    }
}
```

```swift
import XCTest
@testable import ShuttleWebUI

final class ShuttleWebUISmokeTests: XCTestCase {
    func testTargetNameIsStable() {
        XCTAssertEqual(ShuttleWebUIBootstrap.targetName, "ShuttleWebUI")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test`
Expected: FAIL during compilation because `Package.swift` and the `ShuttleServer` or `ShuttleWebUI` target do not exist yet, or because the bootstrap types are undefined.

- [ ] **Step 3: Add minimal manifest and target declarations**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Shuttle",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "ShuttleWebUI", targets: ["ShuttleWebUI"]),
        .executable(name: "ShuttleServer", targets: ["ShuttleServer"]),
    ],
    dependencies: [
        .package(path: "../PositronicKit"),
    ],
    targets: [
        .executableTarget(
            name: "ShuttleServer",
            dependencies: [
                .product(name: "PositronicKit", package: "PositronicKit"),
                .product(name: "PKShared", package: "PositronicKit"),
            ],
            path: "Sources/ShuttleServer"
        ),
        .target(
            name: "ShuttleWebUI",
            path: "Sources/ShuttleWebUI"
        ),
        .testTarget(
            name: "ShuttleServerTests",
            dependencies: ["ShuttleServer"],
            path: "Tests/ShuttleServerTests"
        ),
        .testTarget(
            name: "ShuttleWebUITests",
            dependencies: ["ShuttleWebUI"],
            path: "Tests/ShuttleWebUITests"
        ),
    ]
)
```

- [ ] **Step 4: Run test to verify it still fails for the right reason**

Run: `swift test`
Expected: FAIL during compilation because the `ShuttleServer` or `ShuttleWebUI` sources do not exist yet, or because the bootstrap types are undefined.

### Task 2: Add Minimal Production Code

**Files:**
- Create: `Sources/ShuttleServer/ShuttleServerApp.swift`
- Create: `Sources/ShuttleServer/main.swift`
- Create: `Sources/ShuttleWebUI/ShuttleWebUIBootstrap.swift`
- Test: `Tests/ShuttleServerTests/ShuttleServerSmokeTests.swift`
- Test: `Tests/ShuttleWebUITests/ShuttleWebUISmokeTests.swift`

- [ ] **Step 1: Write minimal implementation**

```swift
public enum ShuttleServerApp {
    public static func makeStartupBanner() -> String {
        "ShuttleServer bootstrap ready"
    }

    public static func main() {
        print(makeStartupBanner())
    }
}
```

```swift
ShuttleServerApp.main()
```

```swift
public enum ShuttleWebUIBootstrap {
    public static let targetName = "ShuttleWebUI"
}
```

- [ ] **Step 2: Run test to verify it passes**

Run: `swift test`
Expected: PASS with `ShuttleServerSmokeTests.testStartupBannerMentionsTargetName` and `ShuttleWebUISmokeTests.testTargetNameIsStable` green.

- [ ] **Step 3: Run build to verify the executable product exists**

Run: `swift build`
Expected: BUILD SUCCEEDED with executable product `ShuttleServer` and library target `ShuttleWebUI`.

- [ ] **Step 4: Commit**

```bash
git add Package.swift Sources/ShuttleServer/ShuttleServerApp.swift Sources/ShuttleServer/main.swift Sources/ShuttleWebUI/ShuttleWebUIBootstrap.swift Tests/ShuttleServerTests/ShuttleServerSmokeTests.swift Tests/ShuttleWebUITests/ShuttleWebUISmokeTests.swift docs/superpowers/plans/2026-05-28-shut-001-package-skeleton.md
git commit -m "feat: bootstrap Shuttle Swift package"
```

## Self-Review

- Spec coverage: satisfies `SHUT-001` acceptance criteria only. It does not attempt `SHUT-002` health routes or `SHUT-003` Docker scaffolding.
- Placeholder scan: no `TBD`, `TODO`, or omitted commands remain.
- Type consistency: `ShuttleServerApp.makeStartupBanner()` and `ShuttleWebUIBootstrap.targetName` are defined in the implementation task and referenced consistently in the tests.
