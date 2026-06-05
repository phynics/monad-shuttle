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

public struct ShuttleDockerClient: Sendable {
    let probeAvailability: @Sendable () async -> ShuttleDockerAvailability

    public init(
        probeAvailability: @escaping @Sendable () async -> ShuttleDockerAvailability
    ) {
        self.probeAvailability = probeAvailability
    }

    func probe() async -> ShuttleDockerAvailability {
        await probeAvailability()
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
