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

        router.get("/api/shards/{id}/events") { request, context in
            guard let databaseQueue else {
                throw HTTPError(.serviceUnavailable)
            }
            guard let shardID = context.parameters.get("id", as: String.self) else {
                throw HTTPError(.badRequest)
            }

            do {
                let pagination = try parsePagination(from: request)
                let shardStore = ShuttleShardStore(dbQueue: databaseQueue)
                guard try shardStore.fetchShard(id: shardID) != nil else {
                    throw HTTPError(.notFound)
                }

                let page = try ShuttleAuditEventStore(dbQueue: databaseQueue).fetchPage(
                    entityType: "shard",
                    entityID: shardID,
                    afterID: pagination.cursor,
                    limit: pagination.limit
                )
                return ShuttleAuditEventPageResponse(
                    items: page.events.map(ShuttleAuditEventResponse.init),
                    nextCursor: page.nextCursor
                )
            } catch {
                throw mapShardAPIError(error)
            }
        }

        router.get("/api/shards/{id}/logs") { request, context in
            guard let databaseQueue, let loadedConfig else {
                throw HTTPError(.serviceUnavailable)
            }
            guard let shardID = context.parameters.get("id", as: String.self) else {
                throw HTTPError(.badRequest)
            }

            do {
                let pagination = try parsePagination(from: request)
                let shardStore = ShuttleShardStore(dbQueue: databaseQueue)
                guard try shardStore.fetchShard(id: shardID) != nil else {
                    throw HTTPError(.notFound)
                }

                let page = try ShuttleCommandLogStore(
                    dbQueue: databaseQueue,
                    logsRootPath: loadedConfig.paths.logsPath,
                    retentionDays: loadedConfig.retention.rawLogsDays,
                    maxBytesPerFile: loadedConfig.retention.rawLogsMaxBytes
                ).fetchPage(
                    shardID: shardID,
                    afterID: pagination.cursor,
                    limit: pagination.limit
                )
                return ShuttleCommandLogPageResponse(
                    items: page.entries.map(ShuttleCommandLogChunkResponse.init),
                    nextCursor: page.nextCursor
                )
            } catch {
                throw mapShardAPIError(error)
            }
        }

        router.get("/api/events") { request, _ in
            guard let databaseQueue else {
                throw HTTPError(.serviceUnavailable)
            }

            do {
                let pagination = try parsePagination(from: request)
                let page = try ShuttleAuditEventStore(dbQueue: databaseQueue).fetchPage(
                    afterID: pagination.cursor,
                    limit: pagination.limit
                )
                return ShuttleAuditEventPageResponse(
                    items: page.events.map(ShuttleAuditEventResponse.init),
                    nextCursor: page.nextCursor
                )
            } catch {
                throw mapShardAPIError(error)
            }
        }

        router.get("/api/conflicts") { _, _ in
            guard let databaseQueue else {
                throw HTTPError(.serviceUnavailable)
            }

            do {
                let conflicts = try ShuttleConflictStore(dbQueue: databaseQueue).fetchAllConflicts()
                return conflicts.map(ShuttleConflictResponse.init)
            } catch {
                throw mapShardAPIError(error)
            }
        }

        router.post("/api/conflicts/{id}/resolve") { request, context in
            guard let databaseQueue, let loadedConfig else {
                throw HTTPError(.serviceUnavailable)
            }
            guard let conflictID = context.parameters.get("id", as: String.self) else {
                throw HTTPError(.badRequest)
            }

            do {
                let body = try await request.decode(as: ShuttleResolveConflictRequest.self, context: context)
                let repositoryStateStore = ShuttleRepositoryStateStore(dbQueue: databaseQueue)
                let conflictStore = ShuttleConflictStore(dbQueue: databaseQueue)
                let auditEventStore = ShuttleAuditEventStore(dbQueue: databaseQueue)
                let service = ShuttleConflictService(
                    repositoryStateStore: repositoryStateStore,
                    conflictStore: conflictStore,
                    config: loadedConfig,
                    auditEventStore: auditEventStore
                )
                let resolved = try service.resolveConflict(
                    conflictID: conflictID,
                    resolutionShardID: body.resolutionShardID
                )
                return ShuttleConflictResponse(conflict: resolved)
            } catch {
                throw mapShardAPIError(error)
            }
        }

        router.post("/api/repository/refresh") { _, _ in
            guard let databaseQueue, let loadedConfig else {
                throw HTTPError(.serviceUnavailable)
            }

            do {
                let repositoryStateStore = ShuttleRepositoryStateStore(dbQueue: databaseQueue)
                let conflictStore = ShuttleConflictStore(dbQueue: databaseQueue)
                let auditEventStore = ShuttleAuditEventStore(dbQueue: databaseQueue)
                let conflictService = ShuttleConflictService(
                    repositoryStateStore: repositoryStateStore,
                    conflictStore: conflictStore,
                    config: loadedConfig,
                    auditEventStore: auditEventStore
                )
                let result = try ShuttleUpstreamRefreshService(
                    config: loadedConfig,
                    repositoryStateStore: repositoryStateStore,
                    conflictService: conflictService
                ).refresh()
                return ShuttleUpstreamRefreshResponse(result: result)
            } catch {
                throw mapShardAPIError(error)
            }
        }

        router.post("/api/pushes") { request, context in
            guard let databaseQueue, let loadedConfig else {
                throw HTTPError(.serviceUnavailable)
            }

            let idempotencyHeader = HTTPField.Name("Idempotency-Key")!
            guard let key = request.headers[idempotencyHeader], !key.isEmpty else {
                throw HTTPError(.badRequest, message: "Missing Idempotency-Key header")
            }

            do {
                let body = try await request.decode(as: ShuttlePushRequest.self, context: context)
                let repositoryStateStore = ShuttleRepositoryStateStore(dbQueue: databaseQueue)
                let shardStore = ShuttleShardStore(dbQueue: databaseQueue)
                let idempotencyStore = ShuttleIdempotencyStore(dbQueue: databaseQueue)
                let auditEventStore = ShuttleAuditEventStore(dbQueue: databaseQueue)
                let pushService = ShuttlePushService(
                    config: loadedConfig,
                    repositoryStateStore: repositoryStateStore,
                    shardStore: shardStore,
                    idempotencyStore: idempotencyStore,
                    auditEventStore: auditEventStore
                )
                let result = try pushService.push(
                    targetName: body.targetName,
                    ref: try parsePushRef(body.ref),
                    idempotencyKey: key,
                    actor: nil
                )
                return ShuttlePushResponse(result: result)
            } catch {
                throw mapShardAPIError(error)
            }
        }
    }
}

private struct ShuttlePaginationRequest {
    let cursor: Int64?
    let limit: Int
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

private func parsePagination(from request: Request, defaultLimit: Int = 50, maxLimit: Int = 200) throws -> ShuttlePaginationRequest {
    let query = request.uri.queryParameters

    let cursor: Int64?
    if let rawCursor = query["cursor"] {
        guard let parsed = Int64(String(rawCursor)), parsed >= 0 else {
            throw HTTPError(.badRequest, message: "Invalid cursor")
        }
        cursor = parsed
    } else {
        cursor = nil
    }

    let limit: Int
    if let rawLimit = query["limit"] {
        guard let parsed = Int(String(rawLimit)), parsed > 0, parsed <= maxLimit else {
            throw HTTPError(.badRequest, message: "Invalid limit")
        }
        limit = parsed
    } else {
        limit = defaultLimit
    }

    return ShuttlePaginationRequest(cursor: cursor, limit: limit)
}

private func parsePushRef(_ request: ShuttlePushRefRequest) throws -> ShuttlePushRef {
    switch request.kind {
    case "shuttle_main":
        return .shuttleMain
    case "retained_shard":
        guard let shardID = request.shardID, !shardID.isEmpty else {
            throw HTTPError(.badRequest, message: "Missing shardID for retained_shard push ref")
        }
        return .retainedShard(shardID: shardID)
    default:
        throw HTTPError(.badRequest, message: "Invalid push ref kind: \(request.kind)")
    }
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

    case let error as ShuttleConflictResolutionValidationError:
        switch error {
        case .repositoryNotClean(let paths):
            return HTTPError(.badRequest, message: "Repository is not clean: \(paths.joined(separator: ", "))")
        case .activeMergeState:
            return HTTPError(.badRequest, message: "Repository has an active merge state")
        }

    case let error as ShuttleConflictStoreError:
        switch error {
        case .invalidDetailsEncoding, .invalidDetailsDecoding:
            return HTTPError(.internalServerError, message: "Invalid conflict details")
        case .conflictNotFound:
            return HTTPError(.notFound)
        case .conflictAlreadyResolved:
            return HTTPError(.badRequest, message: "Conflict is already resolved")
        }

    case let error as ShuttleUpstreamRefreshServiceError:
        switch error {
        case .integrationLocked(let state):
            return HTTPError(.conflict, message: "Repository refresh is blocked by state \(state.rawValue)")
        case .refreshFailed(let message):
            return HTTPError(.internalServerError, message: message)
        }

    case let error as ShuttlePushServiceError:
        switch error {
        case .targetNotConfigured(let target):
            return HTTPError(.badRequest, message: "Push target is not configured: \(target)")
        case .shardNotFound, .runtimeMetadataMissing:
            return HTTPError(.notFound)
        case .shardNotRetained(let shardID):
            return HTTPError(.badRequest, message: "Shard is not retained: \(shardID)")
        case .invalidLocalRef(let ref):
            return HTTPError(.badRequest, message: "Invalid local ref: \(ref)")
        case .idempotencyConflict:
            return HTTPError(.conflict, message: "Idempotency key already used for a different push request")
        case .pushFailed(let message):
            return HTTPError(.internalServerError, message: message)
        }

    case let error as ShuttleRepositoryStateStoreError:
        switch error {
        case .invalidIntegrationState(let state):
            return HTTPError(.internalServerError, message: "Invalid repository state: \(state)")
        case .stateMismatch(_, let actual):
            return HTTPError(.conflict, message: "Repository state changed to \(actual.rawValue)")
        }

    default:
        return error
    }
}
