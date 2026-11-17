import Foundation

/// Siri can include the app destination in an entity's search text.
/// Keep literal titles authoritative and only retry after an empty result.
enum MusicIntentSearch {
    @MainActor
    static func results<Item>(for text: String,
                              search: (String) async throws -> [Item]) async throws -> [Item] {
        let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let results = try await search(term)
        guard results.isEmpty, let fallback = fallbackTerm(for: term) else { return results }
        try Task.checkCancellation()
        return try await search(fallback)
    }

    nonisolated static func fallbackTerm(for text: String) -> String? {
        let term = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Only a trailing destination for this app; never remove words inside a title
        // or redirect a request addressed to another player.
        let pattern = #"(?i)\s+(?:in|on|en|dans|sur|auf|σε|στο|στην)\s+(?:mus1c|minidisc|music)[.!?]?\s*$"#
        guard let range = term.range(of: pattern, options: .regularExpression) else { return nil }
        let stripped = String(term[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? nil : stripped
    }
}
