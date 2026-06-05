import Foundation

struct ShuttleShardWorkspace: Equatable, Sendable {
    let id: String
    let branchName: String
    let worktreePath: String
    let baseCommit: String
}

struct ShuttleShardWorkspaceService {
    let shardStore: ShuttleShardStore
    let worktreeManager: ShuttleWorktreeManager

    init(
        shardStore: ShuttleShardStore,
        worktreeManager: ShuttleWorktreeManager
    ) {
        self.shardStore = shardStore
        self.worktreeManager = worktreeManager
    }

    func createQueuedShard(
        id: String,
        title: String,
        spec: String,
        branchName: String
    ) throws -> ShuttleShardWorkspace {
        if try shardStore.fetchShard(id: id) != nil {
            throw ShuttleShardStoreError.duplicateShard(id)
        }

        let createdWorktree = try worktreeManager.createWorktree(
            shardID: id,
            branchName: branchName
        )

        do {
            try shardStore.createQueuedShard(
                id: id,
                title: title,
                spec: spec,
                baseCommit: createdWorktree.baseCommit,
                branchName: createdWorktree.branchName,
                worktreePath: createdWorktree.worktreePath
            )
        } catch {
            try? worktreeManager.removeWorktree(
                branchName: createdWorktree.branchName,
                worktreePath: createdWorktree.worktreePath
            )
            throw error
        }

        return ShuttleShardWorkspace(
            id: id,
            branchName: createdWorktree.branchName,
            worktreePath: createdWorktree.worktreePath,
            baseCommit: createdWorktree.baseCommit
        )
    }

    func retainDoneShard(
        shardID: String,
        retainedUntil: Date
    ) throws {
        guard let runtimeMetadata = try shardStore.fetchRuntimeMetadata(shardID: shardID) else {
            throw ShuttleShardStoreError.shardNotFound(shardID)
        }

        try worktreeManager.retainReadOnly(worktreePath: runtimeMetadata.worktreePath)
        try shardStore.markDoneRetained(
            shardID: shardID,
            retainedUntil: retainedUntil
        )
    }
}
