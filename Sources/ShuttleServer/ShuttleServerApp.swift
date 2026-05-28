import Foundation
import Hummingbird

public enum ShuttleServerApp {
    public struct Environment: Sendable {
        public let configuration: ShuttleServerConfiguration
        public let statusStore: ShuttleServerStatusStore

        public init(configuration: ShuttleServerConfiguration, statusStore: ShuttleServerStatusStore) {
            self.configuration = configuration
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
        if let configPath = configuration.configPath,
           !FileManager.default.isReadableFile(atPath: configPath) {
            await statusStore.setServerState(.fatal)
            await statusStore.setSubsystem(
                "config",
                status: .init(status: .failed, detail: "Unreadable config path: \(configPath)")
            )
            throw ShuttleStartupError.unreadableConfigPath(configPath)
        }

        return Environment(configuration: configuration, statusStore: statusStore)
    }

    public static func makeRouter(environment: Environment) -> Router<BasicRequestContext> {
        let router = Router(context: BasicRequestContext.self)
        ShuttleServerRoutes.register(on: router, statusStore: environment.statusStore)
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
