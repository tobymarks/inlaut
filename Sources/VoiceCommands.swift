import Foundation

/// Spoken layout commands: "neue Zeile" → line break, "neuer Absatz" →
/// blank line. The recogniser writes them as words with commas around
/// ("Hallo Frau Becker, neuer Absatz, vielen Dank …"), so the punctuation
/// next to each command is tidied as well.
enum VoiceCommands {
    private static let command = try! NSRegularExpression(
        pattern: #"([\s,;:.!?]*)\b(neue[rn]?\s+absatz|neue\s+zeile)\b[\s,;:.!?]*"#,
        options: [.caseInsensitive])

    /// Lines this short are salutations or sign-offs ("Hallo Frau Becker,",
    /// "Viele Grüße,", "Tobias Marks"), which keep their comma or get no period.
    private static let shortLine = 4

    static func apply(to text: String) -> String {
        let ns = text as NSString
        let matches = command.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }

        var out = ""
        var cursor = 0
        for match in matches {
            let line = ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let before = ns.substring(with: match.range(at: 1))
            out += finish(line, punctuationBefore: before, capitalize: cursor > 0)
            let isParagraph = ns.substring(with: match.range(at: 2)).lowercased().contains("absatz")
            out += isParagraph ? "\n\n" : "\n"
            cursor = match.range.location + match.range.length
        }
        var last = capitalized(ns.substring(from: cursor).trimmingCharacters(in: .whitespaces))
        if wordCount(last) <= shortLine, last.hasSuffix(".") { last.removeLast() }  // signature
        out += last
        // Two commands in a row must not stack up more than one blank line.
        while out.contains("\n\n\n") { out = out.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func finish(_ raw: String, punctuationBefore: String, capitalize: Bool) -> String {
        var line = raw.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return "" }
        if capitalize { line = capitalized(line) }
        if let end = line.last, ".!?:;,".contains(end) { return line }
        if let spoken = punctuationBefore.first(where: { ".!?:".contains($0) }) {
            return line + String(spoken)
        }
        // The recogniser put a comma: keep it after a salutation, otherwise
        // the line was a sentence.
        if punctuationBefore.contains(",") {
            return line + (wordCount(line) <= shortLine ? "," : ".")
        }
        return line
    }

    private static func capitalized(_ line: String) -> String {
        guard let first = line.first else { return line }
        return first.uppercased() + line.dropFirst()
    }

    private static func wordCount(_ line: String) -> Int {
        line.split(whereSeparator: \.isWhitespace).count
    }
}
