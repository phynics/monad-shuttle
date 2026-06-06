import Foundation
import GRDB
import PKShared

struct ShuttleAgentTranscriptEntry: Codable, Sendable {
    let shardID: String
    let event: ChatEvent
    let recordedAt: Date
}

struct ShuttleAgentTranscriptStore {
    let dbQueue: DatabaseQueue
    let logsRootPath: String
    let retentionDays: Int
    let maxBytesPerFile: Int

    func append(
        shardID: String,
        event: ChatEvent,
        recordedAt: Date = Date()
    ) throws {
        let entry = ShuttleAgentTranscriptEntry(
            shardID: shardID,
            event: event,
            recordedAt: recordedAt
        )
        let directory = shardDirectory(shardID: shardID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let data = try JSONEncoder().encode(entry)
        let line = data + Data([0x0A])
        let fileURL = try activeLogFileURL(
            shardID: shardID,
            stream: "agent",
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
                    shardID,
                    "agent",
                    fileURL.path,
                    startOffset,
                    endOffset,
                    recordedAt,
                ]
            )
        }
    }

    func fetchEntries(shardID: String) throws -> [ShuttleAgentTranscriptEntry] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT file_path, offset_start, offset_end
                FROM log_indexes
                WHERE shard_id = ? AND stream = 'agent'
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
                return try JSONDecoder().decode(ShuttleAgentTranscriptEntry.self, from: Data(trimmed))
            }
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
}
