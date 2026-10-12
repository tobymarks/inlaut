import Foundation

/// Everything that happens to recognised text before it is pasted or shown,
/// in one place: the settings go in, the finished text comes out.
struct TextPipeline: Sendable {
    var languages: Set<SpokenLanguage>
    var voiceCommands = true
    var sharpS = true
    var replacements: [Replacement] = []
    var snippets: [Snippet] = []

    /// A dictation. A snippet's phrase on its own inserts the snippet as it
    /// was written; anything else gets voice commands, ß and replacements.
    func dictation(_ raw: String) -> String {
        if let snippet = snippets.match(raw) { return snippet }
        return corrected(voiceCommands ? VoiceCommands.apply(to: raw, languages: languages) : raw)
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
