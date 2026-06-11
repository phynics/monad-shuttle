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
            let argument = arguments[index]
            switch argument {
            case "--host":
                index += 1
                guard index < arguments.count else {
                    throw ShuttleStartupError.missingValue(argument)
                }
                host = arguments[index]
            case "--port":
                index += 1
                guard index < arguments.count else {
                    throw ShuttleStartupError.missingValue(argument)
                }
                guard let parsedPort = Int(arguments[index]) else {
                    throw ShuttleStartupError.invalidPort(arguments[index])
                }
                port = parsedPort
            case "--config":
                index += 1
                guard index < arguments.count else {
                    throw ShuttleStartupError.missingValue(argument)
                }
                configPath = arguments[index]
            default:
                break
            }
            index += 1
        }

        return ShuttleServerConfiguration(host: host, port: port, configPath: configPath)
    }
}

public enum ShuttleStartupError: Error, Equatable, Sendable {
    case invalidPort(String)
    case missingValue(String)
    case unreadableConfigPath(String)
    case invalidVolumePath(subsystem: String, path: String)
    case unreadableSSHKeyPath(String)
    case databaseOpenFailed(String)
    case gitOperationFailed(String)
}
