import Foundation
import GRDB
import Hummingbird

public enum ShuttleServerApp {
    public struct Environment: Sendable {
        public let configuration: ShuttleServerConfiguration
        let loadedConfig: ShuttleConfig?
        let managedRepository: ShuttleRepositoryBootstrapResult?
        let databaseQueue: DatabaseQueue?
        let repositoryStateStore: ShuttleRepositoryStateStore?
        let dockerAccessController: ShuttleDockerAccessController
        public let statusStore: ShuttleServerStatusStore

        init(
            configuration: ShuttleServerConfiguration,
            loadedConfig: ShuttleConfig?,
            managedRepository: ShuttleRepositoryBootstrapResult?,
            databaseQueue: DatabaseQueue? = nil,
            repositoryStateStore: ShuttleRepositoryStateStore? = nil,
            dockerAccessController: ShuttleDockerAccessController? = nil,
            statusStore: ShuttleServerStatusStore
        ) {
            self.configuration = configuration
            self.loadedConfig = loadedConfig
            self.managedRepository = managedRepository
            self.databaseQueue = databaseQueue
            self.repositoryStateStore = repositoryStateStore
            self.dockerAccessController = dockerAccessController
                ?? ShuttleDockerAccessController(client: .live(), statusStore: statusStore)
            self.statusStore = statusStore
        }
    }

    public static func makeStartupBanner() -> String {
        "ShuttleServer bootstrap ready"
    }

    public static func makeEnvironment(
        configuration: ShuttleServerConfiguration,
        statusStore: ShuttleServerStatusStore = ShuttleServerStatusStore(),
        dockerClient: ShuttleDockerClient = .live()
    ) async throws -> Environment {
        var loadedConfig: ShuttleConfig?
        var managedRepository: ShuttleRepositoryBootstrapResult?
        var databaseQueue: DatabaseQueue?
        var repositoryStateStore: ShuttleRepositoryStateStore?
        let dockerAccessController = ShuttleDockerAccessController(
            client: dockerClient,
            statusStore: statusStore
        )

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
                let openedDatabase = try await openDatabase(
                    loadedConfig: loadedConfig,
                    statusStore: statusStore
                )
                databaseQueue = openedDatabase
                repositoryStateStore = ShuttleRepositoryStateStore(dbQueue: openedDatabase)
                managedRepository = try await bootstrapManagedRepository(
                    loadedConfig: loadedConfig,
                    statusStore: statusStore
                )
                try ensureRepositoryState(
                    loadedConfig: loadedConfig,
                    repositoryStateStore: repositoryStateStore,
                    managedRepository: managedRepository
                )
                try await reconcileStartupState(
                    loadedConfig: loadedConfig,
                    managedRepository: managedRepository,
                    databaseQueue: openedDatabase,
                    repositoryStateStore: repositoryStateStore,
                    dockerAccessController: dockerAccessController,
                    statusStore: statusStore
                )
                try await cleanupRetainedState(
                    loadedConfig: loadedConfig,
                    managedRepository: managedRepository,
                    databaseQueue: openedDatabase,
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

        _ = await dockerAccessController.probeHealth()

        return Environment(
            configuration: configuration,
            loadedConfig: loadedConfig,
            managedRepository: managedRepository,
            databaseQueue: databaseQueue,
            repositoryStateStore: repositoryStateStore,
            dockerAccessController: dockerAccessController,
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
            ("database", (loadedConfig.paths.databasePath as NSString).deletingLastPathComponent, "database volume"),
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

    private static func bootstrapManagedRepository(
        loadedConfig: ShuttleConfig?,
        statusStore: ShuttleServerStatusStore
    ) async throws -> ShuttleRepositoryBootstrapResult? {
        guard let loadedConfig else {
            return nil
        }

        do {
            return try ShuttleRepositoryBootstrapper.bootstrap(config: loadedConfig)
        } catch let startupError as ShuttleStartupError {
            await statusStore.setServerState(.fatal)
            await statusStore.setSubsystem(
                "git",
                status: .init(status: .failed, detail: String(describing: startupError))
            )
            throw startupError
        } catch let shellError as ShuttleGitShellError {
            let detail: String
            switch shellError {
            case .commandFailed(let command, let status, let stderr):
                detail = "Git command failed (\(status)): git \(command.joined(separator: " ")) \(stderr)"
            case .invalidOutputEncoding(let command):
                detail = "Git output decoding failed: git \(command.joined(separator: " "))"
            }
            await statusStore.setServerState(.fatal)
            await statusStore.setSubsystem("git", status: .init(status: .failed, detail: detail))
            throw ShuttleStartupError.gitOperationFailed(detail)
        } catch {
            let detail = "Unexpected git bootstrap error: \(error)"
            await statusStore.setServerState(.fatal)
            await statusStore.setSubsystem("git", status: .init(status: .failed, detail: detail))
            throw ShuttleStartupError.gitOperationFailed(detail)
        }
    }

    private static func openDatabase(
        loadedConfig: ShuttleConfig?,
        statusStore: ShuttleServerStatusStore
    ) async throws -> DatabaseQueue {
        guard let loadedConfig else {
            throw ShuttleStartupError.databaseOpenFailed("Missing loaded config for database startup")
        }

        do {
            return try ShuttleDatabase.openMigrated(atPath: loadedConfig.paths.databasePath)
        } catch {
            await statusStore.setServerState(.fatal)
            await statusStore.setSubsystem(
                "database",
                status: .init(status: .failed, detail: "Database open failed: \(error)")
            )
            throw ShuttleStartupError.databaseOpenFailed(String(describing: error))
        }
    }

    private static func ensureRepositoryState(
        loadedConfig: ShuttleConfig?,
        repositoryStateStore: ShuttleRepositoryStateStore?,
        managedRepository: ShuttleRepositoryBootstrapResult?
    ) throws {
        guard let loadedConfig, let repositoryStateStore, let managedRepository else {
            return
        }

        if try repositoryStateStore.fetch() == nil {
            try repositoryStateStore.upsert(
                config: loadedConfig,
                integrationState: .open,
                shuttleMainCommit: try ShuttleGitShell.run(
                    ["--git-dir", managedRepository.bareRepositoryPath, "rev-parse", "refs/heads/\(managedRepository.shuttleMainBranch)"]
                ).stdout,
                blockedConflictID: nil
            )
        }
    }

    private static func reconcileStartupState(
        loadedConfig: ShuttleConfig?,
        managedRepository: ShuttleRepositoryBootstrapResult?,
        databaseQueue: DatabaseQueue,
        repositoryStateStore: ShuttleRepositoryStateStore?,
        dockerAccessController: ShuttleDockerAccessController,
        statusStore: ShuttleServerStatusStore
    ) async throws {
        guard let loadedConfig, let managedRepository, let repositoryStateStore else {
            return
        }

        let reconciliationService = ShuttleStartupReconciliationService(
            config: loadedConfig,
            managedRepository: managedRepository,
            shardStore: ShuttleShardStore(dbQueue: databaseQueue),
            repositoryStateStore: repositoryStateStore,
            conflictStore: ShuttleConflictStore(dbQueue: databaseQueue),
            auditEventStore: ShuttleAuditEventStore(dbQueue: databaseQueue),
            dockerAccessController: dockerAccessController
        )

        do {
            try await reconciliationService.reconcile()
        } catch {
            let detail = "Startup reconciliation failed: \(error)"
            await statusStore.setServerState(.fatal)
            await statusStore.setSubsystem(
                "repo_refresh",
                status: .init(status: .failed, detail: detail)
            )
            throw ShuttleStartupError.gitOperationFailed(detail)
        }
    }

    private static func cleanupRetainedState(
        loadedConfig: ShuttleConfig?,
        managedRepository: ShuttleRepositoryBootstrapResult?,
        databaseQueue: DatabaseQueue,
        statusStore: ShuttleServerStatusStore
    ) async throws {
        guard let loadedConfig, let managedRepository else {
            return
        }

        let cleanupService = ShuttleRetentionCleanupService(
            config: loadedConfig,
            shardStore: ShuttleShardStore(dbQueue: databaseQueue),
            auditEventStore: ShuttleAuditEventStore(dbQueue: databaseQueue),
            worktreeManager: ShuttleWorktreeManager(
                bareRepositoryPath: managedRepository.bareRepositoryPath,
                worktreesRootPath: loadedConfig.paths.worktreesPath
            ),
            commandLogStore: ShuttleCommandLogStore(
                dbQueue: databaseQueue,
                logsRootPath: loadedConfig.paths.logsPath,
                retentionDays: loadedConfig.retention.rawLogsDays,
                maxBytesPerFile: loadedConfig.retention.rawLogsMaxBytes
            ),
            agentTranscriptStore: ShuttleAgentTranscriptStore(
                dbQueue: databaseQueue,
                logsRootPath: loadedConfig.paths.logsPath,
                retentionDays: loadedConfig.retention.rawLogsDays,
                maxBytesPerFile: loadedConfig.retention.rawLogsMaxBytes
            )
        )

        do {
            _ = try cleanupService.cleanup()
        } catch {
            let detail = "Retention cleanup failed: \(error)"
            await statusStore.setServerState(.fatal)
            await statusStore.setSubsystem(
                "volumes",
                status: .init(status: .failed, detail: detail)
            )
            throw ShuttleStartupError.gitOperationFailed(detail)
        }
    }

    public static func makeRouter(environment: Environment) -> Router<BasicRequestContext> {
        let router = Router(context: BasicRequestContext.self)
        ShuttleServerRoutes.register(
            on: router,
            statusStore: environment.statusStore,
            loadedConfig: environment.loadedConfig,
            repositoryStateStore: environment.repositoryStateStore,
            databaseQueue: environment.databaseQueue
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
