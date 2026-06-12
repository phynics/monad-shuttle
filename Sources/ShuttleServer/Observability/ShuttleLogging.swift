import Foundation
import Logging

enum ShuttleLogCategory: String, Sendable {
    case startup
    case http
    case docker
    case git
    case runtime
    case shard
    case integration
    case refresh
    case retention
    case conflict
    case push
}

enum ShuttleLogBootstrap {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var didBootstrap = false
    nonisolated(unsafe) private static var configuredLogLevel: Logger.Level = .info

    static func bootstrapIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard !didBootstrap else { return }
        configuredLogLevel = ShuttleLogConfiguration.logLevel(
            from: ProcessInfo.processInfo.environment["SHUTTLE_LOG_LEVEL"]
        )
        LoggingSystem.bootstrap { label in
            ShuttleJSONLogHandler(label: label)
        }
        didBootstrap = true
    }

    static var logLevel: Logger.Level {
        bootstrapIfNeeded()
        return configuredLogLevel
    }
}

enum ShuttleLogFactory {
    static func make(_ category: ShuttleLogCategory) -> Logger {
        make(category, inheriting: nil)
    }

    static func make(_ category: ShuttleLogCategory, inheriting base: Logger?) -> Logger {
        ShuttleLogBootstrap.bootstrapIfNeeded()
        var logger = Logger(label: "shuttle.\(category.rawValue)")
        if let base {
            logger = logger.withMetadata(ShuttleLogMetadata.requestContext(from: base))
        }
        logger.logLevel = ShuttleLogBootstrap.logLevel
        logger[metadataKey: "category"] = .string(category.rawValue)
        return logger
    }
}

enum ShuttleLogField {
    static let requestID = "request_id"
    static let shardID = "shard_id"
    static let conflictID = "conflict_id"
    static let actorType = "actor_type"
    static let actorID = "actor_id"
    static let repoState = "repo_state"
    static let shardState = "shard_state"
    static let branch = "branch"
    static let worktreePath = "worktree_path"
    static let containerName = "container_name"
    static let operation = "operation"
    static let outcome = "outcome"
    static let durationMS = "duration_ms"
    static let errorCode = "error_code"
    static let httpMethod = "http_method"
    static let httpPath = "http_path"
    static let httpStatus = "http_status"
}

extension Logger {
    func withMetadata(_ metadata: Metadata) -> Logger {
        var logger = self
        for (key, value) in metadata {
            logger[metadataKey: key] = value
        }
        return logger
    }
}

enum ShuttleLogMetadata {
    static func shard(_ shardID: String) -> Logger.Metadata {
        [ShuttleLogField.shardID: .string(shardID)]
    }

    static func conflict(_ conflictID: String) -> Logger.Metadata {
        [ShuttleLogField.conflictID: .string(conflictID)]
    }

    static func actor(_ actor: ShuttleActorIdentity?) -> Logger.Metadata {
        guard let actor else { return [:] }
        return [
            ShuttleLogField.actorType: .string(actor.actorType),
            ShuttleLogField.actorID: .string(actor.actorID),
        ]
    }

    static func requestContext(from logger: Logger) -> Logger.Metadata {
        let keys = [
            "hb.request.id",
            ShuttleLogField.requestID,
            ShuttleLogField.httpMethod,
            ShuttleLogField.httpPath,
        ]

        var metadata: Logger.Metadata = [:]
        for key in keys {
            if let value = logger[metadataKey: key] {
                metadata[key] = value
            }
        }
        return metadata
    }
}

enum ShuttleLogConfiguration {
    static func logLevel(from rawValue: String?) -> Logger.Level {
        guard let rawValue else { return .info }

        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "trace":
            return .trace
        case "debug":
            return .debug
        case "info":
            return .info
        case "notice":
            return .notice
        case "warning":
            return .warning
        case "error":
            return .error
        case "critical":
            return .critical
        default:
            return .info
        }
    }
}

private struct ShuttleJSONLogHandler: LogHandler {
    let label: String
    var metadata: Logger.Metadata = [:]
    var logLevel: Logger.Level = .info

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(event: Logging.LogEvent) {
        let level = event.level
        let message = event.message
        let explicitMetadata = event.metadata
        let source = event.source
        let file = event.file
        let function = event.function
        let line = event.line
        let mergedMetadata = merged(base: metadata, override: explicitMetadata)
        let payload = ShuttleStructuredLogEvent(
            timestamp: Self.timestampString(),
            level: level.rawValue,
            label: label,
            message: message.description,
            metadata: ShuttleLogRedaction.redact(metadata: mergedMetadata),
            source: source,
            file: (file as NSString).lastPathComponent,
            function: function,
            line: Int(line)
        )
        ShuttleLogSink.shared.emit(payload, severity: level)
    }

    private func merged(base: Logger.Metadata, override: Logger.Metadata?) -> Logger.Metadata {
        guard let override, !override.isEmpty else { return base }
        var merged = base
        for (key, value) in override {
            merged[key] = value
        }
        return merged
    }

    private static func timestampString() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}

private struct ShuttleStructuredLogEvent: Encodable {
    let timestamp: String
    let level: String
    let label: String
    let message: String
    let metadata: [String: JSONValue]
    let source: String
    let file: String
    let function: String
    let line: Int
}

private enum JSONValue: Encodable, Equatable {
    case string(String)
    case object([String: JSONValue])
    case array([JSONValue])

    func encode(to encoder: Encoder) throws {
        switch self {
        case .string(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .object(let value):
            try value.encode(to: encoder)
        case .array(let value):
            try value.encode(to: encoder)
        }
    }
}

private enum ShuttleLogRedaction {
    private static let sensitiveKeyFragments = [
        "secret",
        "token",
        "password",
        "authorization",
        "ssh_key",
        "private_key",
        "config_blob",
    ]

    static func redact(metadata: Logger.Metadata) -> [String: JSONValue] {
        var redacted: [String: JSONValue] = [:]
        for (key, value) in metadata {
            let lowercasedKey = key.lowercased()
            if sensitiveKeyFragments.contains(where: lowercasedKey.contains) {
                redacted[key] = .string("<redacted>")
            } else {
                redacted[key] = normalize(value)
            }
        }
        return redacted
    }

    private static func normalize(_ value: Logger.MetadataValue) -> JSONValue {
        switch value {
        case .string(let string):
            return .string(string)
        case .stringConvertible(let value):
            return .string(String(describing: value))
        case .array(let values):
            return .array(values.map(normalize))
        case .dictionary(let values):
            return .object(values.mapValues(normalize))
        @unknown default:
            return .string(String(describing: value))
        }
    }
}

private final class ShuttleLogSink: @unchecked Sendable {
    static let shared = ShuttleLogSink()

    private let lock = NSLock()
    private var captureHandlers: [UUID: (String) -> Void] = [:]

    func emit(_ payload: ShuttleStructuredLogEvent, severity: Logger.Level) {
        guard let data = try? JSONEncoder.shuttleLogging.encode(payload),
              let line = String(data: data, encoding: .utf8),
              let lineData = "\(line)\n".data(using: .utf8) else {
            return
        }

        lock.lock()
        let handlers = Array(captureHandlers.values)
        if severity >= .error {
            FileHandle.standardError.write(lineData)
        } else {
            FileHandle.standardOutput.write(lineData)
        }
        lock.unlock()
        for handler in handlers {
            handler(line)
        }
    }

    func addCaptureHandler(_ handler: @escaping (String) -> Void) -> UUID {
        let id = UUID()
        lock.lock()
        captureHandlers[id] = handler
        lock.unlock()
        return id
    }

    func removeCaptureHandler(id: UUID) {
        lock.lock()
        captureHandlers.removeValue(forKey: id)
        lock.unlock()
    }
}

enum ShuttleLogTestSupport {
    static func captureLogs<T>(
        while operation: () async throws -> T
    ) async rethrows -> (result: T, lines: [String]) {
        let lines = LockedLogLines()
        let token = ShuttleLogSink.shared.addCaptureHandler(lines.append)
        defer {
            ShuttleLogSink.shared.removeCaptureHandler(id: token)
        }
        let result = try await operation()
        return (result, lines.snapshot())
    }
}

private final class LockedLogLines: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func append(_ line: String) {
        lock.lock()
        lines.append(line)
        lock.unlock()
    }

    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }
}

private extension JSONEncoder {
    static let shuttleLogging: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}
