import Foundation

enum ShuttleConfigError: Error, Equatable, Sendable {
    case unreadableFile(String)
    case invalidYAML(String)
    case missingRequiredField(String)
    case unknownField(String)
    case invalidType(field: String, expected: String)
    case invalidValue(field: String, reason: String)
    case invalidPath(field: String, reason: String)
    case duplicateField(String)
}
