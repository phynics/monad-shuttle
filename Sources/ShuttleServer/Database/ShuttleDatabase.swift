import Foundation
import GRDB

enum ShuttleDatabase {
    static func openMigrated(atPath path: String) throws -> DatabaseQueue {
        let queue = try DatabaseQueue(path: path)
        try migrator.migrate(queue)
        return queue
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial_schema") { db in
            try db.create(table: "repository_state") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("repo_url", .text).notNull()
                table.column("source_branch", .text).notNull()
                table.column("shuttle_main_branch", .text).notNull().defaults(to: "shuttle-main")
                table.column("upstream_head_commit", .text)
                table.column("shuttle_main_commit", .text)
                table.column("integration_state", .text).notNull().defaults(to: "open")
                table.column("blocked_conflict_id", .text)
                table.column("created_at", .datetime).notNull()
                table.column("updated_at", .datetime).notNull()
            }

            try db.create(table: "shards") { table in
                table.column("id", .text).primaryKey()
                table.column("title", .text).notNull()
                table.column("spec", .text).notNull()
                table.column("state", .text).notNull()
                table.column("base_commit", .text).notNull()
                table.column("retained_until", .datetime)
                table.column("created_at", .datetime).notNull()
                table.column("updated_at", .datetime).notNull()
            }

            try db.create(table: "conflicts") { table in
                table.column("id", .text).primaryKey()
                table.column("kind", .text).notNull()
                table.column("state", .text).notNull()
                table.column("blocking", .boolean).notNull().defaults(to: true)
                table.column("source_shard_id", .text).references("shards", onDelete: .setNull)
                table.column("resolution_shard_id", .text).references("shards", onDelete: .setNull)
                table.column("details_json", .text)
                table.column("created_at", .datetime).notNull()
                table.column("updated_at", .datetime).notNull()
            }

            try db.create(table: "shard_runtime_metadata") { table in
                table.column("shard_id", .text).primaryKey().references("shards", onDelete: .cascade)
                table.column("branch_name", .text).notNull()
                table.column("worktree_path", .text).notNull()
                table.column("container_name", .text).notNull()
                table.column("container_status", .text).notNull()
                table.column("updated_at", .datetime).notNull()
            }

            try db.create(table: "completion_reports") { table in
                table.column("shard_id", .text).primaryKey().references("shards", onDelete: .cascade)
                table.column("summary", .text).notNull()
                table.column("files_changed_json", .text).notNull()
                table.column("checks_json", .text).notNull()
                table.column("risks_json", .text).notNull()
                table.column("created_at", .datetime).notNull()
            }

            try db.create(table: "audit_events") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("timestamp", .datetime).notNull()
                table.column("actor_type", .text)
                table.column("actor_id", .text)
                table.column("entity_type", .text).notNull()
                table.column("entity_id", .text).notNull()
                table.column("event_type", .text).notNull()
                table.column("payload_json", .text).notNull()
            }
            try db.create(index: "idx_audit_events_entity", on: "audit_events", columns: ["entity_type", "entity_id"])

            try db.create(table: "idempotency_keys") { table in
                table.column("idempotency_key", .text).primaryKey()
                table.column("scope", .text).notNull()
                table.column("request_hash", .text).notNull()
                table.column("response_json", .text).notNull()
                table.column("created_at", .datetime).notNull()
                table.column("expires_at", .datetime)
            }

            try db.create(table: "log_indexes") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("shard_id", .text).notNull().references("shards", onDelete: .cascade)
                table.column("stream", .text).notNull()
                table.column("file_path", .text).notNull()
                table.column("offset_start", .integer).notNull()
                table.column("offset_end", .integer).notNull()
                table.column("created_at", .datetime).notNull()
            }
            try db.create(index: "idx_log_indexes_shard_id", on: "log_indexes", columns: ["shard_id"])
        }

        return migrator
    }
}
