import Foundation
import GRDB

struct ShuttleCompletionReportCheck: Codable, Equatable, Sendable {
    let name: String
    let status: String
    let kind: String
}

struct ShuttleCompletionReport: Equatable, Sendable {
    let shardID: String
    let summary: String
    let filesChanged: [String]
    let checks: [ShuttleCompletionReportCheck]
    let risks: [String]
    let createdAt: Date

    var validationStatuses: [ShuttleCompletionReportCheck] {
        checks.filter { $0.kind == "validation_command" }
    }
}

enum ShuttleCompletionReportStoreError: Error, Equatable, Sendable {
    case invalidEncoding
    case invalidDecoding
}

struct ShuttleCompletionReportStore {
    let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    func save(_ report: ShuttleCompletionReport) throws {
        let filesChangedJSON = try encode(report.filesChanged)
        let checksJSON = try encode(report.checks)
        let risksJSON = try encode(report.risks)

        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO completion_reports (shard_id, summary, files_changed_json, checks_json, risks_json, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(shard_id) DO UPDATE SET
                    summary = excluded.summary,
                    files_changed_json = excluded.files_changed_json,
                    checks_json = excluded.checks_json,
                    risks_json = excluded.risks_json,
                    created_at = excluded.created_at
                """,
                arguments: [
                    report.shardID,
                    report.summary,
                    filesChangedJSON,
                    checksJSON,
                    risksJSON,
                    report.createdAt,
                ]
            )
        }
    }

    func fetch(shardID: String) throws -> ShuttleCompletionReport? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                SELECT shard_id, summary, files_changed_json, checks_json, risks_json, created_at
                FROM completion_reports
                WHERE shard_id = ?
                """,
                arguments: [shardID]
            ) else {
                return nil
            }

            let filesChanged: [String] = try decode(row["files_changed_json"])
            let checks: [ShuttleCompletionReportCheck] = try decode(row["checks_json"])
            let risks: [String] = try decode(row["risks_json"])

            return ShuttleCompletionReport(
                shardID: row["shard_id"],
                summary: row["summary"],
                filesChanged: filesChanged,
                checks: checks,
                risks: risks,
                createdAt: row["created_at"]
            )
        }
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw ShuttleCompletionReportStoreError.invalidEncoding
        }
        return string
    }

    private func decode<T: Decodable>(_ json: String) throws -> T {
        guard let data = json.data(using: .utf8) else {
            throw ShuttleCompletionReportStoreError.invalidDecoding
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ShuttleCompletionReportStoreError.invalidDecoding
        }
    }
}
