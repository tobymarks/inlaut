import Foundation

/// Restores ß where the recogniser writes ss. parakeet-primeline was trained
/// on text without ß ("Strasse", "Grüsse"), so every German user would
/// otherwise build the same replacement list.
///
/// Only word parts whose ss spelling is never correct in standard German are
/// listed. They also match inside compounds ("Hauptstrasse", "regelmässig"),
/// so each part is anchored as tightly as needed to stay clear of compound
/// joints such as "Hinweis|schild" or "aus|senden". Pairs where both spellings
/// are words (Masse/Maße, Busse/Buße, floss/Floß) are left alone.
enum SharpS {
    private enum Anchor { case anywhere, start, startOrEnd, word }

    private struct Rule {
        let key: String       // lowercase, as recognised
        let sharpS: Int       // offset of the ss in `key`
        let anchor: Anchor
        let unless: [String]  // words containing one of these stay as they are

        init(_ spelled: String, _ anchor: Anchor = .anywhere, unless: [String] = []) {
            let chars = Array(spelled)
            sharpS = chars.firstIndex(of: "ß")!
            key = spelled.replacingOccurrences(of: "ß", with: "ss")
            self.anchor = anchor
            self.unless = unless
        }
    }

    private static let rules: [Rule] = [
        // Adjectives and adverbs
        Rule("groß", unless: ["grossist"]),  // großartig, Großstadt, riesengroß
        Rule("größ"),                        // größer, Größe, größtenteils
        Rule("bloß", unless: ["blossom"]),
        Rule("heiß"),                        // heißen, heißt, verheißen, Scheiße
        Rule("süß"),                         // Süßigkeiten, Süßwasser
        Rule("fleiß"),
        Rule("gemäß"),                       // zeitgemäß, ordnungsgemäß
        Rule("mäßig"),                       // regelmäßig, mäßigen
        Rule("weiß", .startOrEnd, unless: ["weissag"]),  // weißt, Weißwein, Eiweiß – not Hinweis|schild
        Rule("schweiß"),                     // schweißen
        Rule("außen", .start, unless: ["aussende", "aussendung", "aussenk"]),  // not aus|senden
        Rule("außer", .start),               // außerdem, außerhalb
        Rule("draußen", .word),
        Rule("äuß"),                         // äußern, äußerst, Äußerung
        // Nouns
        Rule("straße"),                      // Straßen, Hauptstraße
        Rule("fuß", unless: ["fussel"]),     // Fußball, barfuß
        Rule("füße", .word),                 // not the town Füssen
        Rule("gruß"),
        Rule("grüß"),                        // grüßen, Grüße
        Rule("spaß"),
        Rule("späß"),
        Rule("maßnahm"),
        Rule("maßstab"),
        Rule("maßgeb"),                      // maßgeblich, maßgebend
        Rule("maßgeschneider"),
        Rule("maßeinheit"),
        Rule("ausmaß"),
        Rule("übermaß"),
        Rule("gefäß"),
        Rule("spieß"),                       // spießig
        Rule("soße"),
        Rule("stoß"),                        // anstoßen, Zusammenstoß
        Rule("stöß"),
        Rule("reißverschluss"),              // reiß alone would hit Preis|senkung
        // Verbs with a long vowel before the ß
        Rule("ließ"),                        // ließ, schließen, fließend, verließ
        Rule("hieß"),                        // hieß, schießen
        Rule("gieß"),
        Rule("genieß"),
        Rule("beiß"),
    ]

    private static let word = try! NSRegularExpression(pattern: #"\p{L}+"#)

    static func apply(to text: String) -> String {
        let ns = text as NSString
        var out = ""
        var cursor = 0
        for match in word.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            out += correct(ns.substring(with: match.range))
            cursor = match.range.location + match.range.length
        }
        return out + ns.substring(from: cursor)
    }

    private static func correct(_ original: String) -> String {
        let chars = Array(original)
        let lower = Array(original.lowercased())
        // Lowercasing may change the length (rare ligatures); leave such words alone.
        guard chars.count == lower.count, lower.count >= 4 else { return original }
        let lowered = String(lower)

        var sharp = Set<Int>()  // index of the first s of each ss to replace
        for rule in rules where !rule.unless.contains(where: lowered.contains) {
            let key = Array(rule.key)
            var start = 0
            while start + key.count <= lower.count {
                if Array(lower[start..<start + key.count]) == key, fits(rule.anchor, start, key.count, lower.count) {
                    sharp.insert(start + rule.sharpS)
                }
                start += 1
            }
        }
        guard !sharp.isEmpty else { return original }

        var out = ""
        var index = 0
        while index < chars.count {
            // Capitals keep SS, the usual spelling of ß in uppercase text.
            if sharp.contains(index), chars[index] == "s", chars[index + 1] == "s" {
                out.append("ß")
                index += 2
            } else {
                out.append(chars[index])
                index += 1
            }
        }
        return out
    }

    private static func fits(_ anchor: Anchor, _ start: Int, _ length: Int, _ total: Int) -> Bool {
        switch anchor {
        case .anywhere: true
        case .start: start == 0
        case .startOrEnd: start == 0 || start + length == total
        case .word: start == 0 && length == total
        }
    }
}
