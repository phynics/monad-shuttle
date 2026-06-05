import Foundation

public enum ShuttleDockerAccessError: Error, Equatable, Sendable {
    case unavailable(operation: String, detail: String)
}

actor ShuttleDockerAccessController {
    private let client: ShuttleDockerClient
    private let statusStore: ShuttleServerStatusStore
    private var lastAvailability: ShuttleDockerAvailability?

    init(
        client: ShuttleDockerClient,
        statusStore: ShuttleServerStatusStore
    ) {
        self.client = client
        self.statusStore = statusStore
    }

    @discardableResult
    func probeHealth() async -> ShuttleDockerAvailability {
        let availability = await client.probe()
        lastAvailability = availability
        await statusStore.setSubsystem(
            "docker",
            status: .init(
                status: availability.isAvailable ? .ok : .failed,
                detail: availability.detail
            )
        )
        return availability
    }

    func requireAvailable(for operation: String) async throws {
        let availability: ShuttleDockerAvailability
        if let lastAvailability {
            availability = lastAvailability
        } else {
            availability = await probeHealth()
        }
        guard availability.isAvailable else {
            throw ShuttleDockerAccessError.unavailable(
                operation: operation,
                detail: availability.detail ?? "Docker is unavailable"
            )
        }
    }

    func withDockerAccess<T: Sendable>(
        operation: String,
        _ body: @Sendable () async throws -> T
    ) async throws -> T {
        try await requireAvailable(for: operation)
        return try await body()
    }

    func createContainer(_ request: ShuttleDockerCreateContainerRequest) async throws -> ShuttleDockerContainerInspection {
        try await client.createContainer(request)
    }

    func inspectContainer(named name: String) async throws -> ShuttleDockerContainerInspection? {
        try await client.inspectContainer(named: name)
    }

    func stopContainer(named name: String) async throws {
        try await client.stopContainer(named: name)
    }
}
