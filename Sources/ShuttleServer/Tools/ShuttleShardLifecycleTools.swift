import Foundation
import PKShared

enum ShuttleShardLifecycleToolFactory {
    static func makeLifecycleTools(
        shardID: String,
        lifecycleService: ShuttleShardLifecycleService
    ) -> [AnyTool] {
        [
            AnyTool(ShuttleFinishShardTool(shardID: shardID, lifecycleService: lifecycleService)),
            AnyTool(ShuttleRequestInputTool(shardID: shardID, lifecycleService: lifecycleService)),
            AnyTool(ShuttleAbandonShardTool(shardID: shardID, lifecycleService: lifecycleService)),
        ]
    }
}

private struct ShuttleFinishShardTool: Tool, Sendable {
    let id = "finish_shard"
    let name = "Finish Shard"
    let description = "Submit a structured completion report and move the shard to integration"
    let requiresPermission = false

    let shardID: String
    let lifecycleService: ShuttleShardLifecycleService

    func canExecute() async -> Bool {
        true
    }

    var parametersSchema: [String: AnyCodable] {
        [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "summary": [
                    "type": AnyCodable("string"),
                    "description": AnyCodable("A concise summary of what was completed"),
                ],
                "files_changed": [
                    "type": AnyCodable("array"),
                    "items": AnyCodable(["type": AnyCodable("string")]),
                    "description": AnyCodable("Files changed while completing the shard"),
                ],
                "checks": [
                    "type": AnyCodable("array"),
                    "items": AnyCodable([
                        "type": AnyCodable("object"),
                        "properties": AnyCodable([
                            "name": AnyCodable(["type": AnyCodable("string")]),
                            "status": AnyCodable(["type": AnyCodable("string")]),
                            "kind": AnyCodable(["type": AnyCodable("string")]),
                        ]),
                        "required": AnyCodable(["name", "status", "kind"]),
                    ]),
                    "description": AnyCodable("Checks run by the agent, including validation command statuses"),
                ],
                "risks": [
                    "type": AnyCodable("array"),
                    "items": AnyCodable(["type": AnyCodable("string")]),
                    "description": AnyCodable("Known risks or follow-up concerns"),
                ],
            ]),
            "required": AnyCodable(["summary", "files_changed", "checks", "risks"]),
        ]
    }

    func execute(parameters: [String: Any]) async throws -> ToolResult {
        let params = ToolParameters(parameters)
        do {
            let summary = try params.require("summary", as: String.self)
            let filesChanged = try params.require("files_changed", as: [String].self)
            let riskItems = try params.require("risks", as: [String].self)
            let checkItems = try params.require("checks", as: [[String: String]].self)

            let checks = checkItems.map {
                ShuttleCompletionReportCheck(
                    name: $0["name"] ?? "",
                    status: $0["status"] ?? "",
                    kind: $0["kind"] ?? ""
                )
            }

            try await lifecycleService.finishShard(
                shardID: shardID,
                report: ShuttleCompletionReport(
                    shardID: shardID,
                    summary: summary,
                    filesChanged: filesChanged,
                    checks: checks,
                    risks: riskItems,
                    createdAt: Date()
                )
            )
            return .success("Shard marked ready for integration")
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}

private struct ShuttleRequestInputTool: Tool, Sendable {
    let id = "request_input"
    let name = "Request Input"
    let description = "Pause the shard and request human or API input"
    let requiresPermission = false

    let shardID: String
    let lifecycleService: ShuttleShardLifecycleService

    func canExecute() async -> Bool {
        true
    }

    var parametersSchema: [String: AnyCodable] {
        [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "question": [
                    "type": AnyCodable("string"),
                    "description": AnyCodable("The concrete question that needs an answer"),
                ],
                "details": [
                    "type": AnyCodable("string"),
                    "description": AnyCodable("Optional context explaining why input is needed"),
                ],
            ]),
            "required": AnyCodable(["question"]),
        ]
    }

    func execute(parameters: [String: Any]) async throws -> ToolResult {
        let params = ToolParameters(parameters)
        do {
            let question = try params.require("question", as: String.self)
            let details = params.optional("details", as: String.self)
            try await lifecycleService.requestInput(
                shardID: shardID,
                question: question,
                details: details
            )
            return .success("Shard moved to needs_input")
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}

private struct ShuttleAbandonShardTool: Tool, Sendable {
    let id = "abandon_shard"
    let name = "Abandon Shard"
    let description = "Explicitly abandon the shard"
    let requiresPermission = false

    let shardID: String
    let lifecycleService: ShuttleShardLifecycleService

    func canExecute() async -> Bool {
        true
    }

    var parametersSchema: [String: AnyCodable] {
        [
            "type": AnyCodable("object"),
            "properties": AnyCodable([
                "reason": [
                    "type": AnyCodable("string"),
                    "description": AnyCodable("Why the shard is being abandoned"),
                ],
            ]),
            "required": AnyCodable(["reason"]),
        ]
    }

    func execute(parameters: [String: Any]) async throws -> ToolResult {
        let params = ToolParameters(parameters)
        do {
            let reason = try params.require("reason", as: String.self)
            try await lifecycleService.abandonShard(
                shardID: shardID,
                reason: reason
            )
            return .success("Shard abandoned")
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}
