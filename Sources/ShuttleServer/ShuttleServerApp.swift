import Foundation
import Hummingbird

public enum ShuttleServerApp {
    public struct Environment: Sendable {
        public let configuration: ShuttleServerConfiguration
        let loadedConfig: ShuttleConfig?
        public let statusStore: ShuttleServerStatusStore

        init(
            configuration: ShuttleServerConfiguration,
            loadedConfig: ShuttleConfig?,
            statusStore: ShuttleServerStatusStore
        ) {
            self.configuration = configuration
            self.loadedConfig = loadedConfig
            self.statusStore = statusStore
        }
    }

    public static func makeStartupBanner() -> String {
        "ShuttleServer bootstrap ready"
    }

    public static func makeEnvironment(
        configuration: ShuttleServerConfiguration,
        statusStore: ShuttleServerStatusStore = ShuttleServerStatusStore()
    ) async throws -> Environment {
        var loadedConfig: ShuttleConfig?

        if let configPath = configuration.configPath,
           !FileManager.default.isReadableFile(atPath: configPath) {
            await statusStore.setServerState(.fatal)
            await statusStore.setSubsystem(
                "config",
                status: .init(status: .failed, detail: "Unreadable config path: \(configPath)")
            )
            throw ShuttleStartupError.unreadableConfigPath(configPath)
        }

        if let configPath = configuration.configPath {
            do {
                loadedConfig = try ShuttleConfigLoader.load(fromFilePath: configPath)
                try await validateStartupPaths(
                    loadedConfig: loadedConfig,
                    configPath: configPath,
                    statusStore: statusStore
                )
            } catch let startupError as ShuttleStartupError {
                throw startupError
            } catch {
                await statusStore.setServerState(.fatal)
                await statusStore.setSubsystem(
                    "config",
                    status: .init(status: .failed, detail: "Invalid config: \(error)")
                )
                throw error
            }
        }

        return Environment(
            configuration: configuration,
            loadedConfig: loadedConfig,
            statusStore: statusStore
        )
    }

    private static func validateStartupPaths(
        loadedConfig: ShuttleConfig?,
        configPath: String,
        statusStore: ShuttleServerStatusStore
    ) async throws {
        guard let loadedConfig else {
            return
        }

        func fail(subsystem: String, detail: String, error: ShuttleStartupError) async throws -> Never {
            await statusStore.setServerState(.fatal)
            await statusStore.setSubsystem(subsystem, status: .init(status: .failed, detail: detail))
            throw error
        }

        let fileManager = FileManager.default
        let volumeChecks: [(subsystem: String, path: String, label: String)] = [
            ("database", loadedConfig.paths.databasePath, "database volume"),
            ("git", loadedConfig.paths.gitPath, "git volume"),
            ("volumes", loadedConfig.paths.worktreesPath, "worktree volume"),
            ("volumes", loadedConfig.paths.logsPath, "log volume"),
            ("config", (configPath as NSString).deletingLastPathComponent, "config volume"),
            ("config", (loadedConfig.repository.sshKeyPath as NSString).deletingLastPathComponent, "secrets volume"),
        ]

        for check in volumeChecks {
            var isDirectory: ObjCBool = false
            if !fileManager.fileExists(atPath: check.path, isDirectory: &isDirectory) || !isDirectory.boolValue {
                try await fail(
                    subsystem: check.subsystem,
                    detail: "Missing \(check.label) path: \(check.path)",
                    error: .invalidVolumePath(subsystem: check.subsystem, path: check.path)
                )
            }
        }

        if !fileManager.isReadableFile(atPath: loadedConfig.repository.sshKeyPath) {
            try await fail(
                subsystem: "config",
                detail: "Unreadable SSH key path: \(loadedConfig.repository.sshKeyPath)",
                error: .unreadableSSHKeyPath(loadedConfig.repository.sshKeyPath)
            )
        }
    }

    public static func makeRouter(environment: Environment) -> Router<BasicRequestContext> {
        let router = Router(context: BasicRequestContext.self)
        ShuttleServerRoutes.register(
            on: router,
            statusStore: environment.statusStore,
            loadedConfig: environment.loadedConfig
        )
        return router
    }

    public static func main(_ arguments: [String] = CommandLine.arguments) async throws {
        let configuration = try ShuttleServerConfiguration.fromCommandLine(arguments)
        let environment = try await makeEnvironment(configuration: configuration)
        let router = makeRouter(environment: environment)
        let app = Application(
            router: router,
            configuration: .init(
                address: .hostname(environment.configuration.host, port: environment.configuration.port)
            )
        )

        print(makeStartupBanner())
        try await app.runService()
    }
}
