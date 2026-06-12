import Foundation
import Hummingbird
import HTTPTypes
import Logging

struct ShuttleRequestLoggingMiddleware<Context: RequestContext>: RouterMiddleware {
    private let requestIDHeader = HTTPField.Name("X-Request-ID")!

    func handle(
        _ request: Request,
        context: Context,
        next: (Request, Context) async throws -> Response
    ) async throws -> Response {
        var context = context
        let requestID = request.headers[requestIDHeader].flatMap(normalizeRequestID) ?? UUID().uuidString.lowercased()
        var logger = context.logger
        logger[metadataKey: "hb.request.id"] = .string(requestID)
        logger[metadataKey: ShuttleLogField.requestID] = .string(requestID)
        logger[metadataKey: ShuttleLogField.httpMethod] = .string(request.method.rawValue)
        logger[metadataKey: ShuttleLogField.httpPath] = .string(request.uri.path)
        context.logger = logger

        let start = ContinuousClock.now

        do {
            var response = try await next(request, context)
            let duration = start.duration(to: .now)
            context.logger.log(
                level: level(for: response.status.code),
                "request_completed",
                metadata: [
                    ShuttleLogField.outcome: .string("success"),
                    ShuttleLogField.httpStatus: .stringConvertible(response.status.code),
                    ShuttleLogField.durationMS: .stringConvertible(duration.milliseconds),
                ]
            )
            response.headers[requestIDHeader] = requestID
            return response
        } catch let error as HTTPError {
            let duration = start.duration(to: .now)
            context.logger.log(
                level: level(for: error.status.code),
                "request_failed",
                metadata: [
                    ShuttleLogField.outcome: .string("error"),
                    ShuttleLogField.httpStatus: .stringConvertible(error.status.code),
                    ShuttleLogField.durationMS: .stringConvertible(duration.milliseconds),
                    ShuttleLogField.errorCode: .string("http_error"),
                ]
            )
            throw error
        } catch {
            let duration = start.duration(to: .now)
            context.logger.log(
                level: .error,
                "request_failed",
                metadata: [
                    ShuttleLogField.outcome: .string("error"),
                    ShuttleLogField.durationMS: .stringConvertible(duration.milliseconds),
                    ShuttleLogField.errorCode: .string("unhandled_error"),
                ]
            )
            throw error
        }
    }

    private func normalizeRequestID(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func level(for statusCode: Int) -> Logger.Level {
        switch statusCode {
        case 500...:
            return .error
        case 400...:
            return .warning
        default:
            return .info
        }
    }
}

private extension Duration {
    var milliseconds: Int64 {
        let components = self.components
        return (Int64(components.seconds) * 1_000) + (Int64(components.attoseconds) / 1_000_000_000_000_000)
    }
}
