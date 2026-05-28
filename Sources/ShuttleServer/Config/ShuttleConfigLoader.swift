import Foundation
import Yams

enum ShuttleConfigLoader {
    static func load(fromFilePath filePath: String) throws -> ShuttleConfig {
        guard FileManager.default.isReadableFile(atPath: filePath) else {
            throw ShuttleConfigError.unreadableFile(filePath)
        }

        let contents = try String(contentsOfFile: filePath, encoding: .utf8)
        let node: Node
        do {
            guard let parsed = try Yams.compose(yaml: contents) else {
                throw ShuttleConfigError.invalidYAML("empty YAML document")
            }
            node = parsed
        } catch let error as ShuttleConfigError {
            throw error
        } catch {
            throw ShuttleConfigError.invalidYAML("invalid YAML document")
        }

        let root = try YAMLMapping(
            node: node,
            fieldPath: "",
            allowedKeys: [
                "auth",
                "instructions",
                "limits",
                "paths",
                "push_targets",
                "refresh",
                "repository",
                "retention",
                "runtime",
                "server",
            ]
        )

        let repository = try loadRepository(from: root.requiredMapping("repository"))
        let runtime = try loadRuntime(from: root.requiredMapping("runtime"))
        let refresh = try loadRefresh(from: root.requiredMapping("refresh"))
        let retention = try loadRetention(from: root.requiredMapping("retention"))
        let limits = try loadLimits(from: root.requiredMapping("limits"))
        let paths = try loadPaths(from: root.optionalMapping("paths"))
        let pushTargets = try loadPushTargets(from: root)
        let auth = try loadAuth(from: root.requiredMapping("auth"))
        let instructions = try loadInstructions(from: root.requiredMapping("instructions"))
        let server = try loadServer(from: root.optionalMapping("server"))

        return ShuttleConfig(
            repository: repository,
            runtime: runtime,
            refresh: refresh,
            retention: retention,
            limits: limits,
            paths: paths,
            pushTargets: pushTargets,
            auth: auth,
            instructions: instructions,
            server: server
        )
    }

    private static func loadRepository(from mapping: YAMLMapping) throws -> ShuttleConfig.Repository {
        try mapping.validateAllowedKeys(["source_branch", "ssh_key_path", "url"])

        let url = try requireNonEmptyString(mapping.requiredString("url"), field: "repository.url")
        let sourceBranch = try requireNonEmptyString(
            mapping.requiredString("source_branch"),
            field: "repository.source_branch"
        )
        let sshKeyPath = try requireAbsolutePath(
            mapping.requiredString("ssh_key_path"),
            field: "repository.ssh_key_path"
        )

        return .init(url: url, sourceBranch: sourceBranch, sshKeyPath: sshKeyPath)
    }

    private static func loadRuntime(from mapping: YAMLMapping) throws -> ShuttleConfig.Runtime {
        try mapping.validateAllowedKeys(["command_policy", "container_image", "container_workdir"])

        let image = try requireNonEmptyString(
            mapping.requiredString("container_image"),
            field: "runtime.container_image"
        )
        let workdir = try requireAbsolutePath(
            mapping.requiredString("container_workdir"),
            field: "runtime.container_workdir"
        )
        let commandPolicy = try loadCommandPolicy(from: mapping.optionalMapping("command_policy"))

        return .init(
            containerImage: image,
            containerWorkdir: workdir,
            commandPolicy: commandPolicy
        )
    }

    private static func loadCommandPolicy(from mapping: YAMLMapping?) throws -> ShuttleConfig.Runtime.CommandPolicy {
        guard let mapping else {
            return .init(allow: [], deny: [])
        }

        try mapping.validateAllowedKeys(["allow", "deny"])

        return .init(
            allow: try mapping.optionalStringArray("allow", field: "runtime.command_policy.allow") ?? [],
            deny: try mapping.optionalStringArray("deny", field: "runtime.command_policy.deny") ?? []
        )
    }

    private static func loadRefresh(from mapping: YAMLMapping) throws -> ShuttleConfig.Refresh {
        try mapping.validateAllowedKeys(["schedule"])
        let schedule = try requireNonEmptyString(
            mapping.requiredString("schedule"),
            field: "refresh.schedule"
        )
        return .init(schedule: schedule)
    }

    private static func loadRetention(from mapping: YAMLMapping) throws -> ShuttleConfig.Retention {
        try mapping.validateAllowedKeys(["raw_logs_days", "raw_logs_max_bytes", "worktree_days"])

        let worktreeDays = try requirePositiveInt(
            mapping.requiredInt("worktree_days"),
            field: "retention.worktree_days"
        )
        let rawLogsDays = try requirePositiveInt(
            mapping.requiredInt("raw_logs_days"),
            field: "retention.raw_logs_days"
        )
        let rawLogsMaxBytes = try requirePositiveInt(
            mapping.requiredInt("raw_logs_max_bytes"),
            field: "retention.raw_logs_max_bytes"
        )

        return .init(
            worktreeDays: worktreeDays,
            rawLogsDays: rawLogsDays,
            rawLogsMaxBytes: rawLogsMaxBytes
        )
    }

    private static func loadLimits(from mapping: YAMLMapping) throws -> ShuttleConfig.Limits {
        try mapping.validateAllowedKeys([
            "max_integrating_shards",
            "max_log_bytes_per_shard",
            "max_queued_shards",
            "max_running_shards",
        ])

        let maxRunningShards = try requirePositiveInt(
            mapping.requiredInt("max_running_shards"),
            field: "limits.max_running_shards"
        )
        let maxIntegratingShards = try requirePositiveInt(
            mapping.requiredInt("max_integrating_shards"),
            field: "limits.max_integrating_shards"
        )
        let maxQueuedShards = try requirePositiveInt(
            mapping.requiredInt("max_queued_shards"),
            field: "limits.max_queued_shards"
        )
        let maxLogBytesPerShard = try requirePositiveInt(
            mapping.requiredInt("max_log_bytes_per_shard"),
            field: "limits.max_log_bytes_per_shard"
        )

        if maxIntegratingShards != 1 {
            throw ShuttleConfigError.invalidValue(
                field: "limits.max_integrating_shards",
                reason: "must be exactly 1"
            )
        }

        return .init(
            maxRunningShards: maxRunningShards,
            maxIntegratingShards: maxIntegratingShards,
            maxQueuedShards: maxQueuedShards,
            maxLogBytesPerShard: maxLogBytesPerShard
        )
    }

    private static func loadPushTargets(from root: YAMLMapping) throws -> [ShuttleConfig.PushTarget] {
        guard let nodes = try root.optionalSequence("push_targets") else {
            return []
        }

        var pushTargets: [ShuttleConfig.PushTarget] = []
        var seenNames: Set<String> = []

        for (index, node) in nodes.enumerated() {
            let fieldPath = "push_targets[\(index)]"
            let mapping = try YAMLMapping(
                node: node,
                fieldPath: fieldPath,
                allowedKeys: ["branch", "name", "remote"]
            )
            let name = try requireNonEmptyString(
                mapping.requiredString("name"),
                field: "\(fieldPath).name"
            )
            let remote = try requireNonEmptyString(
                mapping.requiredString("remote"),
                field: "\(fieldPath).remote"
            )
            let branch = try requireNonEmptyString(
                mapping.requiredString("branch"),
                field: "\(fieldPath).branch"
            )

            if !seenNames.insert(name).inserted {
                throw ShuttleConfigError.invalidValue(
                    field: "\(fieldPath).name",
                    reason: "must be unique"
                )
            }

            pushTargets.append(.init(name: name, remote: remote, branch: branch))
        }

        return pushTargets
    }

    private static func loadPaths(from mapping: YAMLMapping?) throws -> ShuttleConfig.Paths {
        guard let mapping else {
            return .init(
                databasePath: "/data/db",
                gitPath: "/data/git",
                worktreesPath: "/data/worktrees",
                logsPath: "/data/logs"
            )
        }

        try mapping.validateAllowedKeys(["database", "git", "logs", "worktrees"])

        return .init(
            databasePath: try requireAbsolutePath(
                mapping.optionalString("database") ?? "/data/db",
                field: "paths.database"
            ),
            gitPath: try requireAbsolutePath(
                mapping.optionalString("git") ?? "/data/git",
                field: "paths.git"
            ),
            worktreesPath: try requireAbsolutePath(
                mapping.optionalString("worktrees") ?? "/data/worktrees",
                field: "paths.worktrees"
            ),
            logsPath: try requireAbsolutePath(
                mapping.optionalString("logs") ?? "/data/logs",
                field: "paths.logs"
            )
        )
    }

    private static func loadAuth(from mapping: YAMLMapping) throws -> ShuttleConfig.Auth {
        try mapping.validateAllowedKeys(["mode"])
        let modeString = try requireNonEmptyString(mapping.requiredString("mode"), field: "auth.mode")

        guard let mode = ShuttleConfig.Auth.Mode(rawValue: modeString) else {
            throw ShuttleConfigError.invalidValue(
                field: "auth.mode",
                reason: "must be one of: \(ShuttleConfig.Auth.Mode.allCasesDescription)"
            )
        }

        return .init(mode: mode)
    }

    private static func loadInstructions(from mapping: YAMLMapping) throws -> ShuttleConfig.Instructions {
        try mapping.validateAllowedKeys(["file_path"])
        let filePath = try requireAbsolutePath(
            mapping.requiredString("file_path"),
            field: "instructions.file_path"
        )
        return .init(filePath: filePath)
    }

    private static func loadServer(from mapping: YAMLMapping?) throws -> ShuttleConfig.Server {
        guard let mapping else {
            return .init(host: "127.0.0.1", port: 8080)
        }

        try mapping.validateAllowedKeys(["host", "port"])
        let host = try requireNonEmptyString(
            mapping.optionalString("host") ?? "127.0.0.1",
            field: "server.host"
        )
        let port = try requirePositiveInt(
            mapping.optionalInt("port") ?? 8080,
            field: "server.port"
        )

        return .init(host: host, port: port)
    }

    private static func requireNonEmptyString(_ value: String, field: String) throws -> String {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ShuttleConfigError.invalidValue(field: field, reason: "must not be empty")
        }
        return value
    }

    private static func requireAbsolutePath(_ value: String, field: String) throws -> String {
        let path = try requireNonEmptyString(value, field: field)
        guard path.hasPrefix("/") else {
            throw ShuttleConfigError.invalidPath(field: field, reason: "must be an absolute path")
        }
        return path
    }

    private static func requirePositiveInt(_ value: Int, field: String) throws -> Int {
        guard value > 0 else {
            throw ShuttleConfigError.invalidValue(field: field, reason: "must be greater than zero")
        }
        return value
    }
}

private struct YAMLMapping {
    let fieldPath: String
    private let values: [String: Node]

    init(node: Node, fieldPath: String, allowedKeys: Set<String>? = nil) throws {
        guard let mapping = node.mapping else {
            let label = fieldPath.isEmpty ? "<root>" : fieldPath
            throw ShuttleConfigError.invalidType(field: label, expected: "mapping")
        }

        var values: [String: Node] = [:]
        for (keyNode, valueNode) in mapping {
            guard let key = keyNode.string else {
                let label = fieldPath.isEmpty ? "<root>" : fieldPath
                throw ShuttleConfigError.invalidType(field: label, expected: "string keys")
            }
            let childPath = fieldPath.isEmpty ? key : "\(fieldPath).\(key)"
            guard values[key] == nil else {
                throw ShuttleConfigError.duplicateField(childPath)
            }
            values[key] = valueNode
        }

        self.fieldPath = fieldPath
        self.values = values
        if let allowedKeys {
            try validateAllowedKeys(allowedKeys)
        }
    }

    func validateAllowedKeys(_ allowedKeys: Set<String>) throws {
        for key in values.keys.sorted() where !allowedKeys.contains(key) {
            let childPath = fieldPath.isEmpty ? key : "\(fieldPath).\(key)"
            throw ShuttleConfigError.unknownField(childPath)
        }
    }

    func requiredMapping(_ key: String) throws -> YAMLMapping {
        let node = try requiredNode(key)
        let childPath = childPath(for: key)
        return try YAMLMapping(node: node, fieldPath: childPath)
    }

    func optionalMapping(_ key: String) throws -> YAMLMapping? {
        guard let node = values[key] else {
            return nil
        }
        let childPath = childPath(for: key)
        return try YAMLMapping(node: node, fieldPath: childPath)
    }

    func requiredString(_ key: String) throws -> String {
        let node = try requiredNode(key)
        guard let value = node.string else {
            throw ShuttleConfigError.invalidType(field: childPath(for: key), expected: "string")
        }
        return value
    }

    func optionalString(_ key: String) -> String? {
        values[key]?.string
    }

    func requiredInt(_ key: String) throws -> Int {
        let node = try requiredNode(key)
        if let scalar = node.scalar, let value = Int(scalar.string) {
            return value
        }
        throw ShuttleConfigError.invalidType(field: childPath(for: key), expected: "integer")
    }

    func optionalInt(_ key: String) -> Int? {
        guard let scalar = values[key]?.scalar else {
            return nil
        }
        return Int(scalar.string)
    }

    func optionalStringArray(_ key: String, field: String) throws -> [String]? {
        guard let node = values[key] else {
            return nil
        }
        guard let sequence = node.sequence else {
            throw ShuttleConfigError.invalidType(field: field, expected: "sequence")
        }
        return try sequence.enumerated().map { index, item in
            guard let value = item.string else {
                throw ShuttleConfigError.invalidType(
                    field: "\(field)[\(index)]",
                    expected: "string"
                )
            }
            return value
        }
    }

    func optionalSequence(_ key: String) throws -> [Node]? {
        guard let node = values[key] else {
            return nil
        }
        guard let sequence = node.sequence else {
            throw ShuttleConfigError.invalidType(field: childPath(for: key), expected: "sequence")
        }
        return Array(sequence)
    }

    private func requiredNode(_ key: String) throws -> Node {
        guard let node = values[key] else {
            throw ShuttleConfigError.missingRequiredField(childPath(for: key))
        }
        return node
    }

    private func childPath(for key: String) -> String {
        fieldPath.isEmpty ? key : "\(fieldPath).\(key)"
    }
}

private extension ShuttleConfig.Auth.Mode {
    static var allCasesDescription: String {
        [Self.localAdmin.rawValue].joined(separator: ", ")
    }
}
