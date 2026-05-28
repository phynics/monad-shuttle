# SHUT-002 Health Route Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Start a minimal Hummingbird server from `swift run ShuttleServer` and expose `/api/status` with server state and subsystem health.

**Architecture:** This ticket adds a lightweight startup configuration, a server status store actor, a status response model, route registration, and a minimal runtime wrapper. It intentionally avoids full YAML config, persistence, or auth; explicit invalid config is limited to an unreadable `--config` path so the server can enter `fatal` before `SHUT-010`.

**Tech Stack:** Swift 6, SwiftPM, Hummingbird, HummingbirdTesting, XCTest

---

### Task 1: Add Failing Server Tests

**Files:**
- Modify: `Package.swift`
- Create: `Tests/ShuttleServerTests/ShuttleServerStatusRouteTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import Hummingbird
import HummingbirdTesting
@testable import ShuttleServer

final class ShuttleServerStatusRouteTests: XCTestCase {
    func testStatusEndpointReturnsReadyAndSubsystemKeys() async throws {
        let statusStore = ShuttleServerStatusStore()
        let router = Router(context: BasicRequestContext.self)
        ShuttleServerRoutes.register(on: router, statusStore: statusStore)
        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(uri: "/api/status", method: .get) { response in
                XCTAssertEqual(response.status, .ok)

                let payload = try JSONDecoder().decode(ShuttleStatusResponse.self, from: response.body)
                XCTAssertEqual(payload.serverState, .ready)
                XCTAssertEqual(Set(payload.subsystems.keys), [
                    "agent_runtime",
                    "config",
                    "database",
                    "docker",
                    "git",
                    "repo_refresh",
                    "volumes",
                ])
            }
        }
    }

    func testInvalidExplicitConfigPathSetsFatalState() async throws {
        let statusStore = ShuttleServerStatusStore()
        let configuration = ShuttleServerConfiguration(
            host: "127.0.0.1",
            port: 8080,
            configPath: "/path/that/does/not/exist.yml"
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await ShuttleServerApp.makeEnvironment(
                configuration: configuration,
                statusStore: statusStore
            )
        }

        let payload = await statusStore.snapshot()
        XCTAssertEqual(payload.serverState, .fatal)
    }

    func testGracefulShutdownMarksServerDraining() async throws {
        let statusStore = ShuttleServerStatusStore()
        let shutdownCoordinator = ShuttleServerShutdownCoordinator(statusStore: statusStore)

        await shutdownCoordinator.beginGracefulShutdown()

        let payload = await statusStore.snapshot()
        XCTAssertEqual(payload.serverState, .draining)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ShuttleServerStatusRouteTests`
Expected: FAIL because Hummingbird dependencies, route registration, status models, and startup helpers do not exist yet.

### Task 2: Add Minimal Server Runtime

**Files:**
- Modify: `Package.swift`
- Modify: `Sources/ShuttleServer/ShuttleServerApp.swift`
- Modify: `Sources/ShuttleServer/main.swift`
- Create: `Sources/ShuttleServer/HTTP/ShuttleServerRoutes.swift`
- Create: `Sources/ShuttleServer/HTTP/ShuttleStatusResponse.swift`
- Create: `Sources/ShuttleServer/Runtime/ShuttleServerConfiguration.swift`
- Create: `Sources/ShuttleServer/Runtime/ShuttleServerStatusStore.swift`
- Create: `Sources/ShuttleServer/Runtime/ShuttleServerShutdownCoordinator.swift`
- Test: `Tests/ShuttleServerTests/ShuttleServerStatusRouteTests.swift`

- [ ] **Step 1: Write minimal implementation**

```swift
// Package.swift dependencies and targets
.package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0")
```

```swift
// ShuttleStatusResponse.swift
public enum ShuttleServerState: String, Codable, Sendable {
    case ready
    case draining
    case fatal
}

public enum ShuttleSubsystemState: String, Codable, Sendable {
    case ok
    case failed
}

public struct ShuttleSubsystemHealth: Codable, Equatable, Sendable {
    public let status: ShuttleSubsystemState
    public let detail: String?

    public init(status: ShuttleSubsystemState, detail: String? = nil) {
        self.status = status
        self.detail = detail
    }
}

public struct ShuttleStatusResponse: Codable, Equatable, Sendable {
    public let serverState: ShuttleServerState
    public let subsystems: [String: ShuttleSubsystemHealth]
}
```

```swift
// ShuttleServerStatusStore.swift
public actor ShuttleServerStatusStore {
    private var serverState: ShuttleServerState = .ready
    private var subsystems: [String: ShuttleSubsystemHealth] = [
        "database": .init(status: .ok),
        "git": .init(status: .ok),
        "docker": .init(status: .ok),
        "config": .init(status: .ok),
        "volumes": .init(status: .ok),
        "repo_refresh": .init(status: .ok),
        "agent_runtime": .init(status: .ok),
    ]

    public init() {}

    public func snapshot() -> ShuttleStatusResponse {
        ShuttleStatusResponse(serverState: serverState, subsystems: subsystems)
    }

    public func setServerState(_ state: ShuttleServerState) {
        self.serverState = state
    }

    public func setSubsystem(_ name: String, status: ShuttleSubsystemHealth) {
        self.subsystems[name] = status
    }
}
```

```swift
// ShuttleServerConfiguration.swift
import Foundation

public struct ShuttleServerConfiguration: Equatable, Sendable {
    public let host: String
    public let port: Int
    public let configPath: String?

    public init(host: String = "127.0.0.1", port: Int = 8080, configPath: String? = nil) {
        self.host = host
        self.port = port
        self.configPath = configPath
    }

    public static func fromCommandLine(_ arguments: [String]) throws -> ShuttleServerConfiguration {
        var host = "127.0.0.1"
        var port = 8080
        var configPath: String?
        var index = 1

        while index < arguments.count {
            switch arguments[index] {
            case "--host":
                index += 1
                host = arguments[index]
            case "--port":
                index += 1
                guard let parsedPort = Int(arguments[index]) else {
                    throw ShuttleStartupError.invalidPort(arguments[index])
                }
                port = parsedPort
            case "--config":
                index += 1
                configPath = arguments[index]
            default:
                break
            }
            index += 1
        }

        return ShuttleServerConfiguration(host: host, port: port, configPath: configPath)
    }
}

public enum ShuttleStartupError: Error, Equatable {
    case invalidPort(String)
    case unreadableConfigPath(String)
}
```

```swift
// ShuttleServerShutdownCoordinator.swift
public struct ShuttleServerShutdownCoordinator: Sendable {
    private let statusStore: ShuttleServerStatusStore

    public init(statusStore: ShuttleServerStatusStore) {
        self.statusStore = statusStore
    }

    public func beginGracefulShutdown() async {
        await statusStore.setServerState(.draining)
    }
}
```

```swift
// ShuttleServerRoutes.swift
import Hummingbird

public enum ShuttleServerRoutes {
    public static func register(
        on router: Router<BasicRequestContext>,
        statusStore: ShuttleServerStatusStore
    ) {
        router.get("/api/status") { _, _ in
            await statusStore.snapshot()
        }
    }
}
```

```swift
// ShuttleServerApp.swift
import Foundation
import Hummingbird

public enum ShuttleServerApp {
    public struct Environment: Sendable {
        public let configuration: ShuttleServerConfiguration
        public let statusStore: ShuttleServerStatusStore
    }

    public static func makeStartupBanner() -> String {
        "ShuttleServer bootstrap ready"
    }

    public static func makeEnvironment(
        configuration: ShuttleServerConfiguration,
        statusStore: ShuttleServerStatusStore = ShuttleServerStatusStore()
    ) async throws -> Environment {
        if let configPath = configuration.configPath,
           !FileManager.default.isReadableFile(atPath: configPath) {
            await statusStore.setServerState(.fatal)
            await statusStore.setSubsystem("config", status: .init(status: .failed, detail: "Unreadable config path: \(configPath)"))
            throw ShuttleStartupError.unreadableConfigPath(configPath)
        }

        return Environment(configuration: configuration, statusStore: statusStore)
    }

    public static func makeApplication(environment: Environment) -> some ApplicationProtocol {
        let router = Router(context: BasicRequestContext.self)
        ShuttleServerRoutes.register(on: router, statusStore: environment.statusStore)
        return Application(
            router: router,
            configuration: .init(address: .hostname(environment.configuration.host, port: environment.configuration.port))
        )
    }

    public static func main(_ arguments: [String] = CommandLine.arguments) async throws {
        let configuration = try ShuttleServerConfiguration.fromCommandLine(arguments)
        let environment = try await makeEnvironment(configuration: configuration)
        print(makeStartupBanner())
        let app = makeApplication(environment: environment)
        try await app.runService()
    }
}
```

```swift
// main.swift
import Foundation

try await ShuttleServerApp.main()
```

- [ ] **Step 2: Run test to verify it passes**

Run: `swift test --filter ShuttleServerStatusRouteTests`
Expected: PASS with all three tests green.

- [ ] **Step 3: Run package verification**

Run: `swift test`
Expected: PASS with all smoke and status tests green.

Run: `swift build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add Package.swift Package.resolved Sources/ShuttleServer/HTTP/ShuttleServerRoutes.swift Sources/ShuttleServer/HTTP/ShuttleStatusResponse.swift Sources/ShuttleServer/Runtime/ShuttleServerConfiguration.swift Sources/ShuttleServer/Runtime/ShuttleServerStatusStore.swift Sources/ShuttleServer/Runtime/ShuttleServerShutdownCoordinator.swift Sources/ShuttleServer/ShuttleServerApp.swift Sources/ShuttleServer/main.swift Tests/ShuttleServerTests/ShuttleServerStatusRouteTests.swift docs/superpowers/plans/2026-05-28-shut-002-health-route.md
git commit -m "feat: add Shuttle server health route"
```

## Self-Review

- Spec coverage: covers only `SHUT-002` acceptance criteria and intentionally limits invalid config handling to explicit unreadable config path before `SHUT-010`.
- Placeholder scan: no placeholders remain.
- Type consistency: `ShuttleServerConfiguration`, `ShuttleServerStatusStore`, `ShuttleStatusResponse`, and `ShuttleServerShutdownCoordinator` are defined before use and referenced consistently.
