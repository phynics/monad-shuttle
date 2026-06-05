import Foundation

struct ShuttleShardContainerRuntime: Equatable, Sendable {
    let shardID: String
    let containerName: String
    let containerStatus: ShuttleDockerContainerStatus
    let worktreePath: String
}

enum ShuttleShardContainerServiceError: Error, Equatable, Sendable {
    case missingRuntimeMetadata(String)
    case invalidStoredContainerStatus(String)
}

struct ShuttleShardContainerService {
    let shardStore: ShuttleShardStore
    let dockerAccessController: ShuttleDockerAccessController
    let config: ShuttleConfig

    init(
        shardStore: ShuttleShardStore,
        dockerAccessController: ShuttleDockerAccessController,
        config: ShuttleConfig
    ) {
        self.shardStore = shardStore
        self.dockerAccessController = dockerAccessController
        self.config = config
    }

    func createContainer(forShardID shardID: String) async throws -> ShuttleShardContainerRuntime {
        let runtimeMetadata = try loadRuntimeMetadata(forShardID: shardID)
        let containerName = deterministicContainerName(forShardID: shardID)
        let request = makeCreateRequest(
            containerName: containerName,
            worktreePath: runtimeMetadata.worktreePath
        )

        let inspection = try await dockerAccessController.withDockerAccess(operation: "create_container") {
            try await dockerAccessController.createContainer(request)
        }
        try shardStore.updateContainerMetadata(
            shardID: shardID,
            containerName: inspection.name,
            containerStatus: inspection.status.rawValue
        )

        return ShuttleShardContainerRuntime(
            shardID: shardID,
            containerName: inspection.name,
            containerStatus: inspection.status,
            worktreePath: runtimeMetadata.worktreePath
        )
    }

    func inspectContainer(forShardID shardID: String) async throws -> ShuttleDockerContainerInspection {
        let runtimeMetadata = try loadRuntimeMetadata(forShardID: shardID)
        let inspection = try await dockerAccessController.withDockerAccess(operation: "inspect_container") {
            try await dockerAccessController.inspectContainer(named: runtimeMetadata.containerName)
        }
        guard let inspection else {
            throw ShuttleDockerClientError.containerNotFound(runtimeMetadata.containerName)
        }

        try shardStore.updateContainerMetadata(
            shardID: shardID,
            containerName: inspection.name,
            containerStatus: inspection.status.rawValue
        )

        return inspection
    }

    func stopContainer(forShardID shardID: String) async throws {
        let runtimeMetadata = try loadRuntimeMetadata(forShardID: shardID)
        try await dockerAccessController.withDockerAccess(operation: "stop_container") {
            try await dockerAccessController.stopContainer(named: runtimeMetadata.containerName)
        }
        try shardStore.updateContainerMetadata(
            shardID: shardID,
            containerName: runtimeMetadata.containerName,
            containerStatus: ShuttleDockerContainerStatus.stopped.rawValue
        )
    }

    func ensureContainer(forShardID shardID: String) async throws -> ShuttleShardContainerRuntime {
        let runtimeMetadata = try loadRuntimeMetadata(forShardID: shardID)
        _ = try parseStoredStatus(runtimeMetadata.containerStatus)

        let inspection = try await dockerAccessController.withDockerAccess(operation: "inspect_container") {
            try await dockerAccessController.inspectContainer(named: runtimeMetadata.containerName)
        }

        if let inspection {
            try shardStore.updateContainerMetadata(
                shardID: shardID,
                containerName: inspection.name,
                containerStatus: inspection.status.rawValue
            )
            return ShuttleShardContainerRuntime(
                shardID: shardID,
                containerName: inspection.name,
                containerStatus: inspection.status,
                worktreePath: runtimeMetadata.worktreePath
            )
        }

        let request = makeCreateRequest(
            containerName: runtimeMetadata.containerName,
            worktreePath: runtimeMetadata.worktreePath
        )
        let recreated = try await dockerAccessController.withDockerAccess(operation: "create_container") {
            try await dockerAccessController.createContainer(request)
        }
        try shardStore.updateContainerMetadata(
            shardID: shardID,
            containerName: recreated.name,
            containerStatus: recreated.status.rawValue
        )

        return ShuttleShardContainerRuntime(
            shardID: shardID,
            containerName: recreated.name,
            containerStatus: recreated.status,
            worktreePath: runtimeMetadata.worktreePath
        )
    }

    func deterministicContainerName(forShardID shardID: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let sanitized = shardID.lowercased().unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(String(scalar)) : "-"
        }
        return "shuttle-shard-\(String(sanitized))"
    }

    private func loadRuntimeMetadata(forShardID shardID: String) throws -> ShuttleStoredShardRuntimeMetadata {
        guard let runtimeMetadata = try shardStore.fetchRuntimeMetadata(shardID: shardID) else {
            throw ShuttleShardContainerServiceError.missingRuntimeMetadata(shardID)
        }
        return runtimeMetadata
    }

    private func makeCreateRequest(
        containerName: String,
        worktreePath: String
    ) -> ShuttleDockerCreateContainerRequest {
        ShuttleDockerCreateContainerRequest(
            name: containerName,
            image: config.runtime.containerImage,
            mounts: [
                .init(
                    sourcePath: worktreePath,
                    targetPath: config.runtime.containerWorkdir
                )
            ],
            workingDirectory: config.runtime.containerWorkdir
        )
    }

    private func parseStoredStatus(_ status: String) throws -> ShuttleDockerContainerStatus {
        if status == "not_created" {
            return .stopped
        }
        guard let parsed = ShuttleDockerContainerStatus(rawValue: status) else {
            throw ShuttleShardContainerServiceError.invalidStoredContainerStatus(status)
        }
        return parsed
    }
}
