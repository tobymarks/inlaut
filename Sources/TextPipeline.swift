import Foundation

/// Everything that happens to recognised text before it is pasted or shown,
/// in one place: the settings go in, the finished text comes out.
struct TextPipeline: Sendable {
    var languages: Set<SpokenLanguage>
    var voiceCommands = true
    var sharpS = true
    /// Filler sounds and words said twice go.
    var tidy = false
    /// Self-corrections are offered to whoever confirms them; needs `tidy`.
    var corrections = false
    var replacements: [Replacement] = []
    var snippets: [Snippet] = []

    /// A dictation. A snippet's phrase on its own inserts the snippet as it
    /// was written; anything else gets voice commands, tidying, ß and replacements.
    func dictation(_ raw: String) -> String {
        if raw.allSatisfy(\.isWhitespace) { return "" }
        if let snippet = snippets.match(raw) { return snippet }
        return corrected(tidied(raw)).trimmingCharacters(in: VoiceCommands.edgeSpaces)
    }

    /// The same, and a slip the speaker took back goes too if `confirm` agrees.
    nonisolated(nonsending) func dictation(_ raw: String, confirm: (TextPolish.Correction) async -> Bool) async -> String {
        if raw.allSatisfy(\.isWhitespace) { return "" }
        if let snippet = snippets.match(raw) { return snippet }
        var text = tidied(raw)
        if tidy, corrections { text = await TextPolish.resolve(text, languages: languages, confirm: confirm) }
        return corrected(text).trimmingCharacters(in: VoiceCommands.edgeSpaces)
    }

    private func tidied(_ raw: String) -> String {
        let text = voiceCommands ? VoiceCommands.apply(to: raw, languages: languages) : raw
        return tidy ? TextPolish.tidy(text, languages: languages) : text
    }

    /// A piece of a transcribed recording, where "new line" is something
    /// that was said, not a command.
    func transcript(_ raw: String) -> String {
        corrected(raw)
    }

    /// ß and the user's replacements, which come last so they can override ß.
    private func corrected(_ text: String) -> String {
        var text = text
        if sharpS, languages.contains(.german) { text = SharpS.apply(to: text) }
        return replacements.apply(to: text)
    }
}
