import Foundation
import NaturalLanguage

/// Tidying a dictation in two steps, both of which only ever delete words.
/// Rules take out filler sounds and words said twice. A slip the speaker
/// took back ("am Montag, nein, am Dienstag") is found by rules as well; a
/// language model on this Mac is only asked whether it really is one. It
/// never writes text, so it cannot invent, answer or rewrite anything.
///
/// Probe of 2026-10-13 with Apple's on-device model: letting it rewrite the
/// dictation kept the wrong half of a correction in 3 of 6 cases and obeyed
/// "write a poem"; as a yes/no judge it was right in 11 of 12 cases with a
/// clear correction word, but wrong too often after "also" or "ähm", which
/// is why those do not count as correction words.
enum TextPolish {
    // MARK: - Rules

    /// "um" is a German word, so it only counts where nothing but English is dictated.
    static func fillers(for languages: Set<SpokenLanguage>) -> Set<String> {
        var fillers: Set<String> = []
        if languages.contains(.german) { fillers.formUnion(["ähm", "äh", "ähh", "öhm", "öh", "hm", "hmm", "mhm"]) }
        if languages.contains(.english) { fillers.formUnion(["uh", "uhm", "erm", "hmm", "mhm"]) }
        if languages == [.english] { fillers.insert("um") }
        return fillers
    }

    /// Said twice on purpose often enough to leave alone: "die, die das wollen", "that that".
    private static let doubles: Set<String> = ["die", "der", "das", "den", "dem", "sie", "that", "had", "is"]

    /// Filler sounds and immediately repeated words go; nothing else changes.
    static func tidy(_ text: String, languages: Set<SpokenLanguage>) -> String {
        let tokens = tokens(of: text)
        guard !tokens.isEmpty else { return text }
        let fillers = fillers(for: languages)
        var drop = Set(tokens.indices.filter { fillers.contains(tokens[$0].word) })
        let kept = tokens.indices.filter { !drop.contains($0) }
        // The first of two identical runs of up to four words, longest first.
        var position = 0
        while position < kept.count {
            var skipped = false
            for length in stride(from: 4, through: 1, by: -1) where position + 2 * length <= kept.count {
                let first = kept[position..<position + length], second = kept[position + length..<position + 2 * length]
                guard first.map({ tokens[$0].word }) == second.map({ tokens[$0].word }),
                      !second.contains(where: { tokens[$0].startsSentence }) else { continue }
                if length == 1, doubles.contains(tokens[first.first!].word) || !tokens[second.first!].afterComma { continue }
                drop.formUnion(first)
                position += length
                skipped = true
                break
            }
            if !skipped { position += 1 }
        }
        return removing(drop, from: tokens, in: text).trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Self-corrections

    /// Words that take back what was just said.
    static func markers(for languages: Set<SpokenLanguage>) -> [[String]] {
        var markers: [[String]] = []
        if languages.contains(.german) { markers += [["nein"], ["nee"], ["ich", "meine"], ["quatsch"], ["besser", "gesagt"]] }
        if languages.contains(.english) { markers += [["i", "mean"], ["no"], ["sorry"], ["or", "rather"]] }
        return markers
    }

    /// A possible self-correction: the sentence as spoken and without the slip.
    struct Correction: Equatable {
        var spoken: String
        var shorter: String
        var resume: Int      // word in `shorter` to go on searching from
        var skip: Int        // word in `spoken` to go on from if it is none
    }

    /// The next possible self-correction in one sentence, from a given word
    /// on. It needs a correction word after a comma, words before and after
    /// it, and takes back as many words as the speaker repeats around the one
    /// that changed ("bis Freitag, nein, bis Donnerstag" → two), else one word
    /// if the next is of its kind.
    static func correction(in sentence: String, from start: Int = 0, languages: Set<SpokenLanguage>) -> Correction? {
        let tokens = tokens(of: sentence)
        for index in tokens.indices.dropFirst() where index >= start && tokens[index].afterComma {
            guard let marker = markers(for: languages).first(where: { marker in
                index + marker.count < tokens.count && zip(marker, tokens[index...]).allSatisfy { $0 == $1.word }
            }) else { continue }
            let after = index + marker.count
            var taken = 1
            for length in stride(from: 4, through: 2, by: -1) where length <= index && after + length <= tokens.count {
                let same = (0..<length).filter { tokens[index - length + $0].word == tokens[after + $0].word }.count
                if same >= length - 1 { taken = length; break }
            }
            // A single word is only taken back for one of its kind: a name, a
            // number or a property ("September, nein Oktober"), not "fertig, nein, oder".
            if taken == 1, !sameKind(tokens[index - 1], tokens[after], in: sentence) { continue }
            let shorter = removing(Set(index - taken..<after), from: tokens, in: sentence)
            return Correction(spoken: sentence,
                              shorter: shorter, resume: index - taken, skip: index + 1)
        }
        return nil
    }

    private static let replaceable: Set<NLTag> = [.noun, .number, .adjective, .personalName, .placeName, .organizationName]

    private static func sameKind(_ first: Token, _ second: Token, in sentence: String) -> Bool {
        let tagger = NLTagger(tagSchemes: [.nameTypeOrLexicalClass])
        tagger.string = sentence
        let kinds = [first, second].map { tagger.tag(at: $0.range.lowerBound, unit: .word, scheme: .nameTypeOrLexicalClass).0 }
        guard let kind = kinds[0], kind == kinds[1] else { return false }
        return replaceable.contains(kind)
    }

    /// Resolves the self-corrections `confirm` agrees with, sentence by sentence.
    nonisolated(nonsending) static func resolve(_ text: String, languages: Set<SpokenLanguage>,
                        confirm: (Correction) async -> Bool) async -> String {
        var out = ""
        for var sentence in sentences(of: text) {
            var start = 0
            // A sentence rarely holds more than one; three keeps the wait bounded.
            for _ in 0..<3 {
                guard let found = correction(in: sentence, from: start, languages: languages) else { break }
                if await confirm(found) {
                    sentence = found.shorter
                    start = found.resume
                } else {
                    start = found.skip
                }
            }
            out += sentence
        }
        return out
    }

    /// Whether `resolve` would ask at all.
    static func mayContainCorrection(_ text: String, languages: Set<SpokenLanguage>) -> Bool {
        sentences(of: text).contains { correction(in: $0, languages: languages) != nil }
    }

    /// The text cut in front of every word that starts a sentence; joined
    /// again the pieces give the text back unchanged.
    static func sentences(of text: String) -> [String] {
        let starts = tokens(of: text).filter(\.startsSentence).map(\.range.lowerBound).dropFirst()
        var pieces: [String] = [], cursor = text.startIndex
        for start in starts {
            pieces.append(String(text[cursor..<start]))
            cursor = start
        }
        pieces.append(String(text[cursor...]))
        return pieces
    }

    // MARK: - Words

    struct Token {
        var word: String                 // lowercased
        var range: Range<String.Index>
        var startsSentence = false       // first word, or after . ! ? or a line break
        var afterComma = false
    }

    static func tokens(of text: String) -> [Token] {
        var tokens: [Token] = []
        var index = text.startIndex, gap = Substring()
        while index < text.endIndex {
            guard text[index].isLetter || text[index].isNumber else {
                gap.append(text[index])
                index = text.index(after: index)
                continue
            }
            var end = index
            // An apostrophe or a dot between letters stays inside the word: "I'm", "inlaut.de", "3.2".
            while end < text.endIndex, text[end].isLetter || text[end].isNumber
                    || ("'’.".contains(text[end]) && text.index(after: end) < text.endIndex
                        && (text[text.index(after: end)].isLetter || text[text.index(after: end)].isNumber)) {
                end = text.index(after: end)
            }
            tokens.append(Token(word: text[index..<end].lowercased(), range: index..<end,
                                startsSentence: tokens.isEmpty || gap.contains { ".!?".contains($0) || $0.isNewline },
                                afterComma: gap.contains(",")))
            gap = Substring()
            index = end
        }
        return tokens
    }

    /// A comma after these belonged to the word that went: "und, ähm, danach", "bei, äh, zehn".
    private static let joining: Set<String> = [
        "und", "oder", "aber", "dass", "weil", "bei", "mit", "für", "von", "zu", "in", "an", "auf",
        "and", "or", "but", "that", "because", "so", "to", "at", "for", "with", "of",
    ]

    /// Takes the words out. What ended a sentence or broke a line in front of
    /// them stays; a comma stays only if it stood in front of them ("Freitag,
    /// äh, bis Donnerstag"), and a sentence that now starts with another word
    /// gets its capital letter.
    private static func removing(_ drop: Set<Int>, from tokens: [Token], in text: String) -> String {
        guard !drop.isEmpty else { return text }
        func structure(_ gap: String) -> String {
            // Everything up to the last sentence mark or line break: "," + line breaks, "." …
            guard let end = gap.lastIndex(where: { ".!?…:;".contains($0) || $0.isNewline }) else { return "" }
            return String(gap[...end])
        }
        // What ended the sentence in front of the dropped words, and the line
        // breaks said around them, at most a blank line (#20).
        func joined(_ pieces: [String]) -> String {
            let marks = (pieces.first { !$0.isEmpty } ?? "").filter { !$0.isNewline }
            return marks + String(pieces.joined().filter(\.isNewline).prefix(2))
        }
        var out = ""
        var cursor = text.startIndex
        var last: String?                                                  // the word before the gap
        var pending: (first: String, later: [String], capitalize: Bool)?  // gaps of the words dropped so far
        for (index, token) in tokens.enumerated() {
            let gap = String(text[cursor..<token.range.lowerBound])
            cursor = token.range.upperBound
            if drop.contains(index) {
                pending = (pending?.first ?? gap, pending.map { $0.later + [structure(gap)] } ?? [],
                           (pending?.capitalize ?? false) || token.startsSentence)
                continue
            }
            var word = String(text[token.range])
            if let dropped = pending {
                let kept = joined([structure(dropped.first)] + dropped.later + [structure(gap)])
                if out.isEmpty {
                    // Line breaks before the first word are a spoken command (#20).
                    out = String(kept.filter(\.isNewline))
                } else if !kept.isEmpty {
                    out += kept + (kept.last!.isNewline ? "" : " ")
                } else {
                    out += dropped.first.contains(",") && !joining.contains(last ?? "") ? ", " : " "
                }
                if dropped.capitalize { word = word.prefix(1).uppercased() + word.dropFirst() }
                pending = nil
            } else {
                out += gap
            }
            out += word
            last = token.word
        }
        guard let dropped = pending else { return out + text[cursor...] }
        // Words dropped at the end leave what closed the text: "Absatz.\n\n", "Hallo,\n" (#20).
        let tail = joined([structure(dropped.first)] + dropped.later + [String(text[cursor...])])
        return out + (out.isEmpty ? String(tail.filter(\.isNewline)) : tail)
    }
}
