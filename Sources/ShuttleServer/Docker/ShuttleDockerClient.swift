import Foundation

public struct ShuttleDockerAvailability: Equatable, Sendable {
    public let isAvailable: Bool
    public let detail: String?

    public static func available(detail: String? = nil) -> ShuttleDockerAvailability {
        ShuttleDockerAvailability(isAvailable: true, detail: detail)
    }

    public static func unavailable(detail: String) -> ShuttleDockerAvailability {
        ShuttleDockerAvailability(isAvailable: false, detail: detail)
    }
}

public struct ShuttleDockerBindMount: Equatable, Sendable {
    public let sourcePath: String
    public let targetPath: String

    public init(sourcePath: String, targetPath: String) {
        self.sourcePath = sourcePath
        self.targetPath = targetPath
    }
}

public enum ShuttleDockerContainerStatus: String, Equatable, Sendable {
    case running
    case stopped
}

public struct ShuttleDockerCreateContainerRequest: Equatable, Sendable {
    public let name: String
    public let image: String
    public let mounts: [ShuttleDockerBindMount]
    public let workingDirectory: String

    public init(
        name: String,
        image: String,
        mounts: [ShuttleDockerBindMount],
        workingDirectory: String
    ) {
        self.name = name
        self.image = image
        self.mounts = mounts
        self.workingDirectory = workingDirectory
    }
}

public struct ShuttleDockerContainerInspection: Equatable, Sendable {
    public let name: String
    public let image: String
    public let status: ShuttleDockerContainerStatus
    public let mounts: [ShuttleDockerBindMount]
    public let workingDirectory: String

    public init(
        name: String,
        image: String,
        status: ShuttleDockerContainerStatus,
        mounts: [ShuttleDockerBindMount],
        workingDirectory: String
    ) {
        self.name = name
        self.image = image
        self.status = status
        self.mounts = mounts
        self.workingDirectory = workingDirectory
    }
}

public enum ShuttleDockerClientError: Error, Equatable, Sendable {
    case unsupportedOperation(String)
    case containerNotFound(String)
}

public struct ShuttleDockerClient: Sendable {
    let probeAvailability: @Sendable () async -> ShuttleDockerAvailability
    let createContainerHandler: @Sendable (ShuttleDockerCreateContainerRequest) async throws -> ShuttleDockerContainerInspection
    let inspectContainerHandler: @Sendable (String) async throws -> ShuttleDockerContainerInspection?
    let stopContainerHandler: @Sendable (String) async throws -> Void

    public init(
        probeAvailability: @escaping @Sendable () async -> ShuttleDockerAvailability,
        createContainer: @escaping @Sendable (ShuttleDockerCreateContainerRequest) async throws -> ShuttleDockerContainerInspection = { request in
            throw ShuttleDockerClientError.unsupportedOperation("create_container:\(request.name)")
        },
        inspectContainer: @escaping @Sendable (String) async throws -> ShuttleDockerContainerInspection? = { name in
            throw ShuttleDockerClientError.unsupportedOperation("inspect_container:\(name)")
        },
        stopContainer: @escaping @Sendable (String) async throws -> Void = { name in
            throw ShuttleDockerClientError.unsupportedOperation("stop_container:\(name)")
        }
    ) {
        self.probeAvailability = probeAvailability
        self.createContainerHandler = createContainer
        self.inspectContainerHandler = inspectContainer
        self.stopContainerHandler = stopContainer
    }

    func probe() async -> ShuttleDockerAvailability {
        await probeAvailability()
    }

    func createContainer(_ request: ShuttleDockerCreateContainerRequest) async throws -> ShuttleDockerContainerInspection {
        try await createContainerHandler(request)
    }

    func inspectContainer(named name: String) async throws -> ShuttleDockerContainerInspection? {
        try await inspectContainerHandler(name)
    }

    func stopContainer(named name: String) async throws {
        try await stopContainerHandler(name)
    }

    public static func live(
        socketPath: String = "/var/run/docker.sock"
    ) -> ShuttleDockerClient {
        ShuttleDockerClient(probeAvailability: {
            let fileManager = FileManager.default

            guard fileManager.fileExists(atPath: socketPath) else {
                return .unavailable(detail: "Missing Docker socket at \(socketPath)")
            }

            guard fileManager.isReadableFile(atPath: socketPath) else {
                return .unavailable(detail: "Unreadable Docker socket at \(socketPath)")
            }

            do {
                let attributes = try fileManager.attributesOfItem(atPath: socketPath)
                if let type = attributes[.type] as? FileAttributeType, type != .typeSocket {
                    return .unavailable(detail: "Docker socket path is not a socket: \(socketPath)")
                }
            } catch {
                return .unavailable(detail: "Failed to inspect Docker socket at \(socketPath): \(error)")
            }

            return .available(detail: "Docker socket accessible")
        })
    }
}
