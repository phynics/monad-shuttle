import Foundation

enum ShuttleBranchNamer {
    private static let prefix = "shuttle/shards/"
    private static let maxSlugLength = 48
    private static let initialSuffixLength = 8
    private static let suffixGrowthStep = 4

    static func makeBranchName(
        shardID: String,
        title: String,
        spec: String,
        existingBranchNames: [String]
    ) -> String {
        let sourceText = firstNonEmpty(title, spec) ?? "shard"
        let slug = slugify(sourceText)
        let normalizedID = normalizeID(shardID)
        let existing = Set(existingBranchNames)

        var suffixLength = min(initialSuffixLength, normalizedID.count)
        while true {
            let suffix = String(normalizedID.prefix(suffixLength))
            let branchName = "\(prefix)\(slug)-\(suffix)"
            if !existing.contains(branchName) {
                return branchName
            }

            if suffixLength >= normalizedID.count {
                return "\(branchName)-\(normalizedID)"
            }

            suffixLength = min(suffixLength + suffixGrowthStep, normalizedID.count)
        }
    }

    private static func firstNonEmpty(_ title: String, _ spec: String) -> String? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }

        let firstSpecLine = spec
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return firstSpecLine.isEmpty ? nil : firstSpecLine
    }

    private static func slugify(_ input: String) -> String {
        let lowercased = input.lowercased()
        let mapped = lowercased.map { character -> Character in
            if character.isLetter || character.isNumber {
                return character
            }
            return "-"
        }

        var slug = String(mapped)
            .replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        if slug.isEmpty {
            slug = "shard"
        }

        if slug.count > maxSlugLength {
            let index = slug.index(slug.startIndex, offsetBy: maxSlugLength)
            slug = String(slug[..<index]).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        }

        return slug.isEmpty ? "shard" : slug
    }

    private static func normalizeID(_ shardID: String) -> String {
        let normalized = shardID
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        return normalized.isEmpty ? "shardid" : normalized
    }
}
