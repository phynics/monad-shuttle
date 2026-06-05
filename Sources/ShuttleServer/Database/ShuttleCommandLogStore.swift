import Foundation
import GRDB

struct ShuttleCommandLogStore {
    let dbQueue: DatabaseQueue
    let logsRootPath: String

    func append(_ entry: ShuttleCommandLogEntry) throws {
        let directory = URL(fileURLWithPath: logsRootPath, isDirectory: true)
            .appendingPathComponent(entry.shardID, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileURL = directory.appendingPathComponent("commands.jsonl")
        let data = try JSONEncoder().encode(entry)
        let line = data + Data([0x0A])

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
}
