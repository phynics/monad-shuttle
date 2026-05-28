import XCTest

extension XCTestCase {
    func XCTAssertThrowsErrorAsync(
        _ expression: @escaping @Sendable () async throws -> some Any,
        _ message: @autoclosure () -> String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
            XCTFail(message(), file: file, line: line)
        } catch {
        }
    }
}
