import Foundation

enum ShuttlePushRef: Equatable, Sendable {
    case shuttleMain
    case retainedShard(shardID: String)
}

struct ShuttlePushResult: Codable, Equatable, Sendable {
    let pushID: String
    let targetName: String
    let localRef: String
    let remoteRef: String
    let warnings: [String]
    let result: String
}

enum ShuttlePushServiceError: Error, Equatable, Sendable {
    case targetNotConfigured(String)
    case shardNotFound(String)
    case shardNotRetained(String)
    case runtimeMetadataMissing(String)
    case invalidLocalRef(String)
    case idempotencyConflict(String)
    case pushFailed(String)
}

struct ShuttlePushService {
    let config: ShuttleConfig
    let repositoryStateStore: ShuttleRepositoryStateStore
    let shardStore: ShuttleShardStore
    let idempotencyStore: ShuttleIdempotencyStore
    let auditEventStore: ShuttleAuditEventStore

    func push(
        targetName: String,
        ref: ShuttlePushRef,
        idempotencyKey: String,
        actor: ShuttleActorIdentity?
    ) throws -> ShuttlePushResult {
        let target = try configuredTarget(named: targetName)
        let localRef = try resolveLocalRef(for: ref)
        let remoteRef = "refs/heads/\(target.branch)"
        let requestHash = "\(targetName)|\(localRef)|\(remoteRef)"
        let warnings = try currentWarnings()

        let replayProbe = ShuttlePushResult(
            pushID: idempotencyKey,
            targetName: targetName,
            localRef: localRef,
            remoteRef: remoteRef,
            warnings: warnings,
            result: "success"
        )
        let responseJSON = try encode(result: replayProbe)

        let idempotencyResult: ShuttleIdempotencyStoreResult
        do {
            idempotencyResult = try idempotencyStore.recordOrReplay(
                key: idempotencyKey,
                scope: "push",
                requestHash: requestHash,
                responseJSON: responseJSON,
                createdAt: Date(),
                expiresAt: nil
            )
        } catch let error as ShuttleIdempotencyStoreError {
            switch error {
            case .requestMismatch(let key, _):
                throw ShuttlePushServiceError.idempotencyConflict(key)
            }
        }

        switch idempotencyResult {
        case .replayed(let record):
            return try decode(resultJSON: record.responseJSON)
        case .recorded:
            break
        }

        let bareRepositoryPath = ShuttleRepositoryBootstrapper.repositoryPath(for: config)
        do {
            _ = try ShuttleGitShell.run(
                [
                    "--git-dir",
                    bareRepositoryPath,
                    "push",
                    target.remote,
                    "\(localRef):\(remoteRef)",
                ]
            )
        } catch {
            throw ShuttlePushServiceError.pushFailed(error.localizedDescription)
        }

        let result = ShuttlePushResult(
            pushID: idempotencyKey,
            targetName: targetName,
            localRef: localRef,
            remoteRef: remoteRef,
            warnings: warnings,
            result: "success"
        )
        try auditEventStore.recordPushAction(
            pushID: idempotencyKey,
            target: targetName,
            ref: localRef,
            result: "success",
            warnings: warnings,
            actor: actor
        )
        return result
    }

    private func configuredTarget(named name: String) throws -> ShuttleConfig.PushTarget {
        guard let target = config.pushTargets.first(where: { $0.name == name }) else {
            throw ShuttlePushServiceError.targetNotConfigured(name)
        }
        return target
    }

    private func resolveLocalRef(for ref: ShuttlePushRef) throws -> String {
        switch ref {
        case .shuttleMain:
            return "refs/heads/\(ShuttleRepositoryBootstrapper.shuttleMainBranch)"
        case .retainedShard(let shardID):
            guard let shard = try shardStore.fetchShard(id: shardID) else {
                throw ShuttlePushServiceError.shardNotFound(shardID)
            }
            guard shard.state == .done else {
                throw ShuttlePushServiceError.shardNotRetained(shardID)
            }
            guard let runtime = try shardStore.fetchRuntimeMetadata(shardID: shardID) else {
                throw ShuttlePushServiceError.runtimeMetadataMissing(shardID)
            }
            return "refs/heads/\(runtime.branchName)"
        }
    }

    private func currentWarnings() throws -> [String] {
        let state = try repositoryStateStore.fetchIntegrationState()
        guard state != .open else {
            return []
        }
        return ["repository_state:\(state.rawValue)"]
    }

    private func encode(result: ShuttlePushResult) throws -> String {
        let data = try JSONEncoder().encode(result)
        guard let json = String(data: data, encoding: .utf8) else {
            throw ShuttlePushServiceError.pushFailed("invalid push result encoding")
        }
        return json
    }

    private func decode(resultJSON: String) throws -> ShuttlePushResult {
        guard let data = resultJSON.data(using: .utf8) else {
            throw ShuttlePushServiceError.pushFailed("invalid push result decoding")
        }
        return try JSONDecoder().decode(ShuttlePushResult.self, from: data)
    }
}
