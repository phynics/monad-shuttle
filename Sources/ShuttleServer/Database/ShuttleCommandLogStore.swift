import Foundation
import GRDB

struct ShuttleCommandLogIndexEntry: Equatable, Sendable {
    let id: Int64
    let shardID: String
    let stream: String
    let filePath: String
    let offsetStart: Int64
    let offsetEnd: Int64
    let createdAt: Date
    let entry: ShuttleCommandLogEntry
}

struct ShuttleCommandLogPage: Equatable, Sendable {
    let entries: [ShuttleCommandLogIndexEntry]
    let nextCursor: Int64?
}

struct ShuttleCommandLogStore {
    let dbQueue: DatabaseQueue
    let logsRootPath: String
    let retentionDays: Int
    let maxBytesPerFile: Int

    struct CleanupResult: Equatable, Sendable {
        let deletedIndexCount: Int
        let deletedFileCount: Int
    }

    func append(_ entry: ShuttleCommandLogEntry) throws {
        let directory = shardDirectory(shardID: entry.shardID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let data = try JSONEncoder().encode(entry)
        let line = data + Data([0x0A])
        let fileURL = try activeLogFileURL(
            shardID: entry.shardID,
            stream: "command",
            nextLineBytes: line.count
        )

        let startOffset: Int64
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            startOffset = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            let handle = try FileHandle(forWritingTo: fileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            try handle.close()
        } else {
            startOffset = 0
            try line.write(to: fileURL)
        }

        let endOffset = startOffset + Int64(line.count)
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO log_indexes (shard_id, stream, file_path, offset_start, offset_end, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    entry.shardID,
                    "command",
                    fileURL.path,
                    startOffset,
                    endOffset,
                    entry.endedAt,
                ]
            )
        }
    }

    @discardableResult
    func cleanupExpiredEntries(now: Date = Date()) throws -> CleanupResult {
        let cutoff = now.addingTimeInterval(Double(-retentionDays * 24 * 60 * 60))

        let expiredRows: [(id: Int64, filePath: String)] = try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT id, file_path
                FROM log_indexes
                WHERE stream = 'command' AND created_at < ?
                ORDER BY id ASC
                """,
                arguments: [cutoff]
            ).map { row in
                (id: row["id"], filePath: row["file_path"])
            }
        }

        guard !expiredRows.isEmpty else {
            return CleanupResult(deletedIndexCount: 0, deletedFileCount: 0)
        }

        let expiredIDs = expiredRows.map(\.id)
        let candidatePaths = Set(expiredRows.map(\.filePath))

        try dbQueue.write { db in
            for id in expiredIDs {
                try db.execute(
                    sql: "DELETE FROM log_indexes WHERE id = ?",
                    arguments: [id]
                )
            }
        }

        var deletedFiles = 0
        for path in candidatePaths {
            let remainingCount: Int = try dbQueue.read { db in
                try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM log_indexes WHERE file_path = ?",
                    arguments: [path]
                ) ?? 0
            }
            if remainingCount == 0, FileManager.default.fileExists(atPath: path) {
                try FileManager.default.removeItem(atPath: path)
                deletedFiles += 1
            }
        }

        return CleanupResult(
            deletedIndexCount: expiredIDs.count,
            deletedFileCount: deletedFiles
        )
    }

    func fetchEntries(shardID: String) throws -> [ShuttleCommandLogEntry] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT file_path, offset_start, offset_end
                FROM log_indexes
                WHERE shard_id = ? AND stream = 'command'
                ORDER BY id ASC
                """,
                arguments: [shardID]
            )

            return try rows.map { row in
                let filePath: String = row["file_path"]
                let start: Int64 = row["offset_start"]
                let end: Int64 = row["offset_end"]
                let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: filePath))
                try handle.seek(toOffset: UInt64(start))
                let data = try handle.read(upToCount: Int(end - start)) ?? Data()
                try handle.close()
                let trimmed = data.last == 0x0A ? data.dropLast() : data[...]
                return try JSONDecoder().decode(ShuttleCommandLogEntry.self, from: Data(trimmed))
            }
        }
    }

    func fetchPage(
        shardID: String,
        afterID: Int64? = nil,
        limit: Int
    ) throws -> ShuttleCommandLogPage {
        precondition(limit > 0, "limit must be positive")

        return try dbQueue.read { db in
            var sql = """
                SELECT id, shard_id, stream, file_path, offset_start, offset_end, created_at
                FROM log_indexes
                WHERE shard_id = ? AND stream = 'command'
                """
            var arguments = StatementArguments([shardID])
            if let afterID {
                sql += " AND id > ?"
                arguments += [afterID]
            }
            sql += " ORDER BY id ASC LIMIT ?"
            arguments += [limit + 1]

            let rows = try Row.fetchAll(db, sql: sql, arguments: arguments)
            let decoded = try rows.map(decodeIndexEntry(row:))
            let hasMore = decoded.count > limit
            let pageEntries = hasMore ? Array(decoded.prefix(limit)) : decoded
            let nextCursor = hasMore ? pageEntries.last?.id : nil
            return ShuttleCommandLogPage(entries: pageEntries, nextCursor: nextCursor)
        }
    }

    private func shardDirectory(shardID: String) -> URL {
        URL(fileURLWithPath: logsRootPath, isDirectory: true)
            .appendingPathComponent(shardID, isDirectory: true)
    }

    private func activeLogFileURL(
        shardID: String,
        stream: String,
        nextLineBytes: Int
    ) throws -> URL {
        let directory = shardDirectory(shardID: shardID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let existingFiles = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.lastPathComponent.hasPrefix("\(stream)-") && $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let current = existingFiles.last ?? directory.appendingPathComponent("\(stream)-0001.jsonl")
        if !FileManager.default.fileExists(atPath: current.path) {
            return current
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: current.path)
        let currentSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
        if currentSize + nextLineBytes <= maxBytesPerFile {
            return current
        }

        let nextIndex = (extractFileIndex(from: current.lastPathComponent) ?? 1) + 1
        return directory.appendingPathComponent("\(stream)-\(String(format: "%04d", nextIndex)).jsonl")
    }

    private func extractFileIndex(from fileName: String) -> Int? {
        let stem = (fileName as NSString).deletingPathExtension
        guard let suffix = stem.split(separator: "-").last else {
            return nil
        }
        return Int(suffix)
    }

    private func decodeIndexEntry(row: Row) throws -> ShuttleCommandLogIndexEntry {
        let filePath: String = row["file_path"]
        let start: Int64 = row["offset_start"]
        let end: Int64 = row["offset_end"]
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: filePath))
        try handle.seek(toOffset: UInt64(start))
        let data = try handle.read(upToCount: Int(end - start)) ?? Data()
        try handle.close()
        let trimmed = data.last == 0x0A ? data.dropLast() : data[...]
        let entry = try JSONDecoder().decode(ShuttleCommandLogEntry.self, from: Data(trimmed))

        return ShuttleCommandLogIndexEntry(
            id: row["id"],
            shardID: row["shard_id"],
            stream: row["stream"],
            filePath: filePath,
            offsetStart: start,
            offsetEnd: end,
            createdAt: row["created_at"],
            entry: entry
        )
    }
}
