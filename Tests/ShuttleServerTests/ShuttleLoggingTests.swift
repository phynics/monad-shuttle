import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import Logging
import XCTest
@testable import ShuttleServer

final class ShuttleLoggingTests: XCTestCase {
    func testStructuredLoggerEmitsCoreFieldsAndMetadata() async throws {
        let logger = ShuttleLogFactory.make(.runtime).withMetadata([
            ShuttleLogField.operation: .string("unit_test"),
            ShuttleLogField.shardID: .string("shard-123"),
        ])

        let (_, lines) = await ShuttleLogTestSupport.captureLogs {
            logger.info("logging_test_event", metadata: [
                ShuttleLogField.outcome: .string("success"),
            ])
        }

        let event = try XCTUnwrap(parsed(lines: lines).last)
        XCTAssertEqual(event["label"] as? String, "shuttle.runtime")
        XCTAssertEqual(event["message"] as? String, "logging_test_event")
        let metadata = try XCTUnwrap(event["metadata"] as? [String: Any])
        XCTAssertEqual(metadata["category"] as? String, "runtime")
        XCTAssertEqual(metadata[ShuttleLogField.operation] as? String, "unit_test")
        XCTAssertEqual(metadata[ShuttleLogField.shardID] as? String, "shard-123")
        XCTAssertEqual(metadata[ShuttleLogField.outcome] as? String, "success")
    }

    func testStructuredLoggerRedactsSensitiveMetadata() async throws {
        let logger = ShuttleLogFactory.make(.startup)

        let (_, lines) = await ShuttleLogTestSupport.captureLogs {
            logger.error("sensitive_log", metadata: [
                "secret_token": .string("abc123"),
                "ssh_key_path": .string("/secrets/id_ed25519"),
                "safe_value": .string("visible"),
            ])
        }

        let event = try XCTUnwrap(parsed(lines: lines).last)
        let metadata = try XCTUnwrap(event["metadata"] as? [String: Any])
        XCTAssertEqual(metadata["secret_token"] as? String, "<redacted>")
        XCTAssertEqual(metadata["ssh_key_path"] as? String, "<redacted>")
        XCTAssertEqual(metadata["safe_value"] as? String, "visible")
    }

    func testCategoryLoggerInheritsRequestMetadata() async throws {
        var baseLogger = Logger(label: "test.base")
        baseLogger[metadataKey: ShuttleLogField.requestID] = .string("request-123")
        baseLogger[metadataKey: "hb.request.id"] = .string("request-123")
        let logger = ShuttleLogFactory.make(.push, inheriting: baseLogger).withMetadata([
            ShuttleLogField.operation: .string("unit_test"),
        ])

        let (_, lines) = await ShuttleLogTestSupport.captureLogs {
            logger.info("inherited_request_metadata", metadata: [
                ShuttleLogField.outcome: .string("success"),
            ])
        }

        let event = try XCTUnwrap(parsed(lines: lines).last)
        XCTAssertEqual(event["label"] as? String, "shuttle.push")
        let metadata = try XCTUnwrap(event["metadata"] as? [String: Any])
        XCTAssertEqual(metadata["category"] as? String, "push")
        XCTAssertEqual(metadata[ShuttleLogField.requestID] as? String, "request-123")
        XCTAssertEqual(metadata["hb.request.id"] as? String, "request-123")
    }

    func testLogLevelParsingSupportsDebugAndFallsBackToInfo() {
        XCTAssertEqual(ShuttleLogConfiguration.logLevel(from: "debug"), .debug)
        XCTAssertEqual(ShuttleLogConfiguration.logLevel(from: "TRACE"), .trace)
        XCTAssertEqual(ShuttleLogConfiguration.logLevel(from: "bogus"), .info)
        XCTAssertEqual(ShuttleLogConfiguration.logLevel(from: nil), .info)
    }

    func testRequestLoggingGeneratesRequestIDWhenAbsent() async throws {
        ShuttleLogBootstrap.bootstrapIfNeeded()
        let router = Router(context: BasicRequestContext.self)
        router.add(middleware: ShuttleRequestLoggingMiddleware<BasicRequestContext>())
        router.get("/ping") { _, _ in "pong" }
        let app = Application(router: router, logger: ShuttleLogFactory.make(.http))

        let (_, lines) = try await ShuttleLogTestSupport.captureLogs {
            try await app.test(.router) { client in
                try await client.execute(uri: "/ping", method: .get) { response in
                    XCTAssertEqual(response.status, .ok)
                    XCTAssertNotNil(response.headers[HTTPField.Name("X-Request-ID")!])
                }
            }
        }

        let event = try XCTUnwrap(parsed(lines: lines).last(where: { ($0["message"] as? String) == "request_completed" }))
        let metadata = try XCTUnwrap(event["metadata"] as? [String: Any])
        XCTAssertEqual(metadata[ShuttleLogField.httpMethod] as? String, "GET")
        XCTAssertEqual(metadata[ShuttleLogField.httpPath] as? String, "/ping")
        XCTAssertNotNil(metadata[ShuttleLogField.requestID] as? String)
    }

    func testRequestLoggingHonorsInboundRequestID() async throws {
        ShuttleLogBootstrap.bootstrapIfNeeded()
        let router = Router(context: BasicRequestContext.self)
        router.add(middleware: ShuttleRequestLoggingMiddleware<BasicRequestContext>())
        router.get("/ping") { _, _ in "pong" }
        let app = Application(router: router, logger: ShuttleLogFactory.make(.http))
        let headerName = HTTPField.Name("X-Request-ID")!

        let (_, lines) = try await ShuttleLogTestSupport.captureLogs {
            try await app.test(.router) { client in
                try await client.execute(
                    uri: "/ping",
                    method: .get,
                    headers: [headerName: "client-request-123"]
                ) { response in
                    XCTAssertEqual(response.status, .ok)
                    XCTAssertEqual(response.headers[headerName], "client-request-123")
                }
            }
        }

        let event = try XCTUnwrap(parsed(lines: lines).last(where: { ($0["message"] as? String) == "request_completed" }))
        let metadata = try XCTUnwrap(event["metadata"] as? [String: Any])
        XCTAssertEqual(metadata[ShuttleLogField.requestID] as? String, "client-request-123")
    }

    private func parsed(lines: [String]) -> [[String: Any]] {
        lines.compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
    }
}
