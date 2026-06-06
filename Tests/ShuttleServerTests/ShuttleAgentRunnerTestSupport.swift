import Foundation
import PositronicKit
import PKShared
@testable import ShuttleServer

struct ShuttleTestLLMRequest: Sendable {
    let messages: [LLMMessage]
    let toolIDs: [String]
}

struct ShuttleTestToolCall: Sendable {
    let id: String
    let name: String
    let arguments: String
}

actor ShuttleTestLLMService: LLMServiceProtocol {
    private var scenarios: [[LLMStreamChunk]] = []
    private var requests: [ShuttleTestLLMRequest] = []

    var isConfigured: Bool { get async { true } }
    var configuration: LLMConfiguration { get async { .openAI } }

    func loadConfiguration() async {}
    func updateConfiguration(_: LLMConfiguration) async throws {}
    func clearConfiguration() async {}
    func restoreFromBackup() async throws {}
    func exportConfiguration() async throws -> Data { Data() }
    func importConfiguration(from _: Data) async throws {}
    func sendMessage(_: String) async throws -> String { "" }
    func sendMessage(_: String, responseFormat _: LLMResponseFormat?, generationParameters _: GenerationParameters?, useUtilityModel _: Bool) async throws -> String { "" }
    func generateTags(for _: String) async throws -> [String] { [] }
    func generateTitle(for _: [Message]) async throws -> String { "Shard" }
    func evaluateRecallPerformance(transcript _: String, recalledMemories _: [Memory]) async throws -> [String: Double] { [:] }
    func fetchAvailableModels() async throws -> [String]? { ["mock-model"] }

    func getHealthStatus() async -> HealthStatus { .ok }
    func getHealthDetails() async -> [String: String]? { ["mock": "true"] }
    func checkHealth() async -> HealthStatus { .ok }

    func chatStreamWithContext(_ request: LLMChatRequest) async throws -> LLMStreamResult {
        let stream = await chatStream(
            messages: [],
            tools: nil,
            toolChoice: nil,
            responseFormat: nil,
            generationParameters: request.generationParameters,
            useUtilityModel: false,
            useFastModel: request.useFastModel
        )
        return LLMStreamResult(stream: stream, rawPrompt: "unused")
    }

    func chatStream(
        messages: [LLMMessage],
        tools: [LLMToolDefinition]?,
        toolChoice _: LLMToolChoice?,
        responseFormat _: LLMResponseFormat?,
        generationParameters _: GenerationParameters?,
        useUtilityModel _: Bool,
        useFastModel _: Bool
    ) async -> AsyncThrowingStream<LLMStreamChunk, Error> {
        requests.append(
            ShuttleTestLLMRequest(
                messages: messages,
                toolIDs: tools?.map(\.name) ?? []
            )
        )
        let chunks = scenarios.isEmpty ? [textChunk("No scenario configured", finishReason: "stop")] : scenarios.removeFirst()
        return AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }

    func enqueueTextResponse(_ text: String) {
        scenarios.append([textChunk(text, finishReason: "stop")])
    }

    func enqueueToolCallTurn(calls: [ShuttleTestToolCall]) {
        scenarios.append([toolCallChunk(calls: calls)])
    }

    func lastRequest() -> ShuttleTestLLMRequest? {
        requests.last
    }

    private func textChunk(_ content: String, finishReason: String?) -> LLMStreamChunk {
        LLMStreamChunk(
            id: "mock",
            model: "mock-model",
            choices: [
                LLMStreamChoice(
                    index: 0,
                    delta: LLMStreamDelta(role: .assistant, content: content),
                    finishReason: finishReason
                ),
            ]
        )
    }

    private func toolCallChunk(calls: [ShuttleTestToolCall]) -> LLMStreamChunk {
        LLMStreamChunk(
            id: "mock",
            model: "mock-model",
            choices: [
                LLMStreamChoice(
                    index: 0,
                    delta: LLMStreamDelta(
                        role: .assistant,
                        content: nil,
                        toolCalls: calls.enumerated().map { index, call in
                            LLMToolCallDelta(
                                index: index,
                                id: call.id,
                                function: LLMToolCallDeltaFunction(
                                    name: call.name,
                                    arguments: call.arguments
                                )
                            )
                        }
                    ),
                    finishReason: "tool_calls"
                ),
            ]
        )
    }
}

actor ShuttleTestDockerExecBackend {
    private var containers: [String: ShuttleDockerContainerInspection] = [:]

    func create(request: ShuttleDockerCreateContainerRequest) -> ShuttleDockerContainerInspection {
        let inspection = ShuttleDockerContainerInspection(
            name: request.name,
            image: request.image,
            status: .running,
            mounts: request.mounts,
            workingDirectory: request.workingDirectory
        )
        containers[request.name] = inspection
        return inspection
    }

    func inspectContainer(name: String) -> ShuttleDockerContainerInspection? {
        containers[name]
    }

    func stopContainer(name: String) throws {
        guard var inspection = containers[name] else { return }
        inspection = ShuttleDockerContainerInspection(
            name: inspection.name,
            image: inspection.image,
            status: .stopped,
            mounts: inspection.mounts,
            workingDirectory: inspection.workingDirectory
        )
        containers[name] = inspection
    }

    func exec(request: ShuttleDockerExecRequest) throws -> ShuttleDockerExecResult {
        let startedAt = Date()
        return ShuttleDockerExecResult(
            stdout: request.command.first == "git" ? " M README.md" : "ok",
            stderr: "",
            exitCode: 0,
            startedAt: startedAt,
            endedAt: startedAt
        )
    }
}
