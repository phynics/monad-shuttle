import Foundation
import GRDB
import Hummingbird
import HTTPTypes

public enum ShuttleServerRoutes {
    static func register(
        on router: Router<BasicRequestContext>,
        statusStore: ShuttleServerStatusStore,
        loadedConfig: ShuttleConfig? = nil,
        repositoryStateStore: ShuttleRepositoryStateStore? = nil,
        databaseQueue: DatabaseQueue? = nil
    ) {
        router.get("/api/status") { _, _ in
            let repository: ShuttleStatusResponse.Repository?
            if let repositoryStateStore,
               let storedState = try repositoryStateStore.fetch() {
                repository = .init(
                    integrationState: storedState.integrationState.rawValue,
                    sourceBranch: storedState.sourceBranch,
                    shuttleMainBranch: storedState.shuttleMainBranch,
                    blockedConflictID: storedState.blockedConflictID
                )
            } else {
                repository = nil
            }
            return await statusStore.snapshot(repository: repository)
        }

        router.get("/api/config") { _, _ in
            guard let loadedConfig else {
                throw HTTPError(.notFound)
            }
            return ShuttleConfigResponse(redacting: loadedConfig)
        }

        router.post("/api/shards") { request, context in
            guard let loadedConfig, let databaseQueue else {
                throw HTTPError(.serviceUnavailable)
            }
            let idempotencyHeader = HTTPField.Name("Idempotency-Key")!
            guard let key = request.headers[idempotencyHeader], !key.isEmpty else {
                throw HTTPError(.badRequest, message: "Missing Idempotency-Key header")
            }

            do {
                let body = try await request.decode(as: ShuttleCreateShardRequest.self, context: context)
                let shardStore = ShuttleShardStore(dbQueue: databaseQueue)
                let workspaceService = ShuttleShardWorkspaceService(
                    shardStore: shardStore,
                    worktreeManager: ShuttleWorktreeManager(
                        bareRepositoryPath: ShuttleRepositoryBootstrapper.repositoryPath(for: loadedConfig),
                        worktreesRootPath: loadedConfig.paths.worktreesPath
                    )
                )
                let createService = ShuttleShardCreateService(
                    shardStore: shardStore,
                    workspaceService: workspaceService,
                    idempotencyStore: ShuttleIdempotencyStore(dbQueue: databaseQueue),
                    auditEventStore: ShuttleAuditEventStore(dbQueue: databaseQueue)
                )
                let result = try createService.createShard(
                    title: body.title,
                    spec: body.spec,
                    idempotencyKey: key
                )
                return ShuttleCreateShardResponse(shardID: result.shardID)
            } catch {
                throw mapShardAPIError(error)
            }
        }

        router.get("/api/shards") { request, _ in
            guard let databaseQueue else {
                throw HTTPError(.serviceUnavailable)
            }
            let shardStore = ShuttleShardStore(dbQueue: databaseQueue)
            do {
                let stateFilter = try parseStateFilter(request.uri.queryParameters["states"])
                let shards = try shardStore.fetchShards(states: stateFilter)
                let details = try shards.map { shard in
                    try shardStore.fetchShardDetail(id: shard.id)
                }.compactMap { $0 }
                return details.map(ShuttleShardSummaryResponse.init)
            } catch {
                throw mapShardAPIError(error)
            }
        }

        router.get("/api/shards/{id}") { _, context in
            guard let databaseQueue else {
                throw HTTPError(.serviceUnavailable)
            }
            guard let shardID = context.parameters.get("id", as: String.self) else {
                throw HTTPError(.badRequest)
            }
            let shardStore = ShuttleShardStore(dbQueue: databaseQueue)
            do {
                guard let detail = try shardStore.fetchShardDetail(id: shardID) else {
                    throw HTTPError(.notFound)
                }
                return ShuttleShardDetailResponse(detail: detail)
            } catch {
                throw mapShardAPIError(error)
            }
        }

        router.post("/api/shards/{id}/request-finish") { _, context in
            guard let databaseQueue else {
                throw HTTPError(.serviceUnavailable)
            }
            guard let shardID = context.parameters.get("id", as: String.self) else {
                throw HTTPError(.badRequest)
            }
            let shardStore = ShuttleShardStore(dbQueue: databaseQueue)
            let service = ShuttleShardFinishRequestService(
                shardStore: shardStore,
                auditEventStore: ShuttleAuditEventStore(dbQueue: databaseQueue)
            )
            do {
                try await service.requestFinish(shardID: shardID)
                guard let shard = try shardStore.fetchShard(id: shardID) else {
                    throw HTTPError(.notFound)
                }
                return ShuttleShardActionResponse(shardID: shardID, state: shard.state.rawValue)
            } catch {
                throw mapShardAPIError(error)
            }
        }

        router.post("/api/shards/{id}/answer") { request, context in
            guard let databaseQueue else {
                throw HTTPError(.serviceUnavailable)
            }
            guard let shardID = context.parameters.get("id", as: String.self) else {
                throw HTTPError(.badRequest)
            }
            let body = try await request.decode(as: ShuttleAnswerShardRequest.self, context: context)
            let shardStore = ShuttleShardStore(dbQueue: databaseQueue)
            let service = ShuttleShardAnswerService(
                shardStore: shardStore,
                auditEventStore: ShuttleAuditEventStore(dbQueue: databaseQueue)
            )
            do {
                try await service.answer(shardID: shardID, answer: body.answer)
                guard let shard = try shardStore.fetchShard(id: shardID) else {
                    throw HTTPError(.notFound)
                }
                return ShuttleShardActionResponse(shardID: shardID, state: shard.state.rawValue)
            } catch {
                throw mapShardAPIError(error)
            }
        }

        router.post("/api/shards/{id}/abandon") { request, context in
            guard let databaseQueue else {
                throw HTTPError(.serviceUnavailable)
            }
            guard let shardID = context.parameters.get("id", as: String.self) else {
                throw HTTPError(.badRequest)
            }
            let body = try await request.decode(as: ShuttleAbandonShardRequest.self, context: context)
            let shardStore = ShuttleShardStore(dbQueue: databaseQueue)
            let lifecycleService = ShuttleShardLifecycleService(
                shardStore: shardStore,
                completionReportStore: ShuttleCompletionReportStore(dbQueue: databaseQueue),
                auditEventStore: ShuttleAuditEventStore(dbQueue: databaseQueue)
            )
            do {
                try await lifecycleService.abandonShard(shardID: shardID, reason: body.reason)
                guard let shard = try shardStore.fetchShard(id: shardID) else {
                    throw HTTPError(.notFound)
                }
                return ShuttleShardActionResponse(shardID: shardID, state: shard.state.rawValue)
            } catch {
                throw mapShardAPIError(error)
            }
        }
    }
}

private func parseStateFilter(_ rawValue: Substring?) throws -> [ShuttleShardState]? {
    guard let rawValue else {
        return nil
    }

    let values = rawValue.split(separator: ",").map(String.init)
    guard !values.isEmpty else {
        return []
    }

    var states: [ShuttleShardState] = []
    for value in values {
        guard let state = ShuttleShardState(rawValue: value) else {
            throw HTTPError(.badRequest, message: "Invalid shard state filter: \(value)")
        }
        states.append(state)
    }
    return states
}

private func mapShardAPIError(_ error: Error) -> Error {
    if error is HTTPError {
        return error
    }

    switch error {
    case let error as ShuttleShardCreateServiceError:
        switch error {
        case .emptyTitle:
            return HTTPError(.badRequest, message: "Shard title must not be empty")
        case .emptySpec:
            return HTTPError(.badRequest, message: "Shard spec must not be empty")
        case .idempotencyConflict:
            return HTTPError(.conflict, message: "Idempotency key already used for a different shard request")
        case .invalidStoredResponse:
            return HTTPError(.internalServerError, message: "Invalid stored shard create response")
        }

    case let error as ShuttleShardAnswerServiceError:
        switch error {
        case .shardNotFound:
            return HTTPError(.notFound)
        case .invalidShardState(let state):
            return HTTPError(.badRequest, message: "Shard cannot answer input from state \(state)")
        case .emptyAnswer:
            return HTTPError(.badRequest, message: "Shard answer must not be empty")
        }

    case let error as ShuttleShardFinishRequestServiceError:
        switch error {
        case .shardNotFound:
            return HTTPError(.notFound)
        case .invalidShardState(let state):
            return HTTPError(.badRequest, message: "Shard cannot request finish from state \(state)")
        }

    case let error as ShuttleShardLifecycleServiceError:
        switch error {
        case .invalidCompletionReport(let message):
            return HTTPError(.badRequest, message: message)
        }

    case let error as ShuttleShardStoreError:
        switch error {
        case .duplicateShard:
            return HTTPError(.conflict, message: "Shard already exists")
        case .shardNotFound:
            return HTTPError(.notFound)
        case .invalidShardState(let state):
            return HTTPError(.badRequest, message: "Invalid shard state \(state)")
        }

    default:
        return error
    }
}
