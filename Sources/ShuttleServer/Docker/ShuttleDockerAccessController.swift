import Foundation
import Logging

public enum ShuttleDockerAccessError: Error, Equatable, Sendable {
    case unavailable(operation: String, detail: String)
}

actor ShuttleDockerAccessController {
    private let client: ShuttleDockerClient
    private let statusStore: ShuttleServerStatusStore
    private let logger: Logger
    private var lastAvailability: ShuttleDockerAvailability?

    init(
        client: ShuttleDockerClient,
        statusStore: ShuttleServerStatusStore,
        logger: Logger = ShuttleLogFactory.make(.docker)
    ) {
        self.client = client
        self.statusStore = statusStore
        self.logger = logger
    }

    @discardableResult
    func probeHealth() async -> ShuttleDockerAvailability {
        let availability = await client.probe()
        lastAvailability = availability
        logger.log(
            level: availability.isAvailable ? .info : .error,
            "docker_probe_completed",
            metadata: [
                ShuttleLogField.operation: .string("probe"),
                ShuttleLogField.outcome: .string(availability.isAvailable ? "available" : "unavailable"),
            ]
        )
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
            logger.error("docker_unavailable", metadata: [
                ShuttleLogField.operation: .string(operation),
                ShuttleLogField.outcome: .string("error"),
                ShuttleLogField.errorCode: .string("docker_unavailable"),
            ])
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
        let logger = self.logger.withMetadata([
            ShuttleLogField.operation: .string("create_container"),
            ShuttleLogField.containerName: .string(request.name),
        ])
        do {
            let inspection = try await client.createContainer(request)
            logger.info("docker_create_container_succeeded", metadata: [ShuttleLogField.outcome: .string("success")])
            return inspection
        } catch {
            logger.error("docker_create_container_failed", metadata: [
                ShuttleLogField.outcome: .string("error"),
                ShuttleLogField.errorCode: .string("create_container_failed"),
            ])
            throw error
        }
    }

    func inspectContainer(named name: String) async throws -> ShuttleDockerContainerInspection? {
        do {
            let inspection = try await client.inspectContainer(named: name)
            logger.debug("docker_inspect_container_completed", metadata: [
                ShuttleLogField.operation: .string("inspect_container"),
                ShuttleLogField.containerName: .string(name),
                ShuttleLogField.outcome: .string(inspection == nil ? "missing" : "success"),
            ])
            return inspection
        } catch {
            logger.error("docker_inspect_container_failed", metadata: [
                ShuttleLogField.operation: .string("inspect_container"),
                ShuttleLogField.containerName: .string(name),
                ShuttleLogField.outcome: .string("error"),
                ShuttleLogField.errorCode: .string("inspect_container_failed"),
            ])
            throw error
        }
    }

    func stopContainer(named name: String) async throws {
        do {
            try await client.stopContainer(named: name)
            logger.info("docker_stop_container_succeeded", metadata: [
                ShuttleLogField.operation: .string("stop_container"),
                ShuttleLogField.containerName: .string(name),
                ShuttleLogField.outcome: .string("success"),
            ])
        } catch {
            logger.error("docker_stop_container_failed", metadata: [
                ShuttleLogField.operation: .string("stop_container"),
                ShuttleLogField.containerName: .string(name),
                ShuttleLogField.outcome: .string("error"),
                ShuttleLogField.errorCode: .string("stop_container_failed"),
            ])
            throw error
        }
    }

    func execInContainer(_ request: ShuttleDockerExecRequest) async throws -> ShuttleDockerExecResult {
        do {
            let result = try await client.execInContainer(request)
            logger.info("docker_exec_succeeded", metadata: [
                ShuttleLogField.operation: .string("exec_container"),
                ShuttleLogField.containerName: .string(request.containerName),
                ShuttleLogField.outcome: .string("success"),
            ])
            return result
        } catch {
            logger.error("docker_exec_failed", metadata: [
                ShuttleLogField.operation: .string("exec_container"),
                ShuttleLogField.containerName: .string(request.containerName),
                ShuttleLogField.outcome: .string("error"),
                ShuttleLogField.errorCode: .string("exec_container_failed"),
            ])
            throw error
        }
    }
}
