import Foundation

/// Numbers next to a unit come out the way one would type them (#16):
/// "dreiundzwanzig Euro fünfzig" → "23,50 €", "zwanzig Prozent" → "20 %",
/// "am zwölften Oktober" → "am 12. Oktober", "two thirty p.m." → "2:30 pm".
///
/// Parakeet writes almost every dictated number as words, so this reads
/// German and English number words itself. It only changes a number that
/// stands next to a word saying what it is (a currency, percent, a unit,
/// "Uhr"/"a.m.", a month, "Jahr", "Version", "Seite"); a number on its own
/// ("drei Fragen", "eins nach dem anderen", "halb drei") stays as spoken.
enum SmartFormatting {
    static func apply(to text: String, languages: Set<SpokenLanguage>) -> String {
        guard !languages.isEmpty, text.contains(where: { $0.isLetter || $0.isNumber }) else { return text }
        return Formatter(text: text, languages: languages).run()
    }
}

// MARK: - Text as words and the gaps between them

/// `gaps[0] + words[0] + gaps[1] + words[1] + … + words[n-1] + gaps[n]`
/// is the text. A word holds letters and digits, joined by a hyphen or an
/// apostrophe between letters and by "," "." ":" between digits ("3,80",
/// "14.30", "1,250"); "a.m." and "p.m." are one word with their dots.
private struct Words {
    var words: [String] = []
    var gaps: [String] = []

    init(_ text: String) {
        let chars = Array(text)
        func isWordChar(_ c: Character) -> Bool { c.isLetter || c.isWholeNumber }
        func meridiem(at i: Int) -> Bool {
            guard i + 3 < chars.count, i == 0 || !isWordChar(chars[i - 1]),
                  "apAP".contains(chars[i]), chars[i + 1] == ".", "mM".contains(chars[i + 2]), chars[i + 3] == "."
            else { return false }
            return i + 4 == chars.count || !isWordChar(chars[i + 4])
        }
        var gap = ""
        var i = 0
        while i < chars.count {
            if meridiem(at: i) {
                gaps.append(gap); gap = ""
                words.append(String(chars[i ..< i + 4]))
                i += 4
            } else if isWordChar(chars[i]) {
                let start = i
                while i < chars.count {
                    if isWordChar(chars[i]) { i += 1; continue }
                    if i + 1 < chars.count {
                        let before = chars[i - 1], c = chars[i], after = chars[i + 1]
                        if ",.:".contains(c), before.isWholeNumber, after.isWholeNumber { i += 1; continue }
                        if c == "-", isWordChar(before), isWordChar(after) { i += 1; continue }
                        if "'’".contains(c), before.isLetter, after.isLetter { i += 1; continue }
                    }
                    break
                }
                gaps.append(gap); gap = ""
                words.append(String(chars[start ..< i]))
            } else {
                gap.append(chars[i])
                i += 1
            }
        }
        gaps.append(gap)
    }
}

// MARK: - Numbers

/// A number as spoken or written: "3,5" is 3 with the fraction "5".
private struct Amount {
    var integer: Int
    var fraction: String?
    /// The digits as the recogniser wrote them; nil for spoken numbers.
    var written: String?
    var isWhole: Bool { fraction == nil }
}

private enum German {
    static let small: [String: Int] = [
        "ein": 1, "eins": 1, "zwei": 2, "zwo": 2, "drei": 3, "vier": 4, "fünf": 5, "sechs": 6, "sieben": 7,
        "acht": 8, "neun": 9, "zehn": 10, "elf": 11, "zwölf": 12, "dreizehn": 13, "vierzehn": 14,
        "fünfzehn": 15, "sechzehn": 16, "siebzehn": 17, "achtzehn": 18, "neunzehn": 19,
    ]
    static let tens: [String: Int] = [
        "zwanzig": 20, "dreißig": 30, "dreissig": 30, "vierzig": 40, "fünfzig": 50,
        "sechzig": 60, "siebzig": 70, "achtzig": 80, "neunzig": 90,
    ]
    static let digits: [String: String] = [
        "null": "0", "eins": "1", "ein": "1", "zwei": "2", "zwo": "2", "drei": "3", "vier": "4",
        "fünf": "5", "sechs": "6", "sieben": "7", "acht": "8", "neun": "9",
    ]

    /// "dreiundzwanzig" → 23, "eintausendzweihundertfünfzig" → 1250,
    /// "neunzehnhundertneunundneunzig" → 1999.
    static func cardinal(_ s: String) -> Int? {
        if s == "null" { return 0 }
        if let r = s.range(of: "tausend") {
            let head = String(s[..<r.lowerBound]), tail = String(s[r.upperBound...])
            guard let h = head.isEmpty ? 1 : belowThousand(head), h > 0,
                  let t = tail.isEmpty ? 0 : belowThousand(tail.hasPrefix("und") ? String(tail.dropFirst(3)) : tail)
            else { return nil }
            return h * 1000 + t
        }
        return belowThousand(s)
    }

    private static func belowThousand(_ s: String) -> Int? {
        if let r = s.range(of: "hundert") {
            let head = String(s[..<r.lowerBound]), tail = String(s[r.upperBound...])
            guard let h = head.isEmpty ? 1 : belowHundred(head), h > 0,
                  let t = tail.isEmpty ? 0 : belowHundred(tail.hasPrefix("und") ? String(tail.dropFirst(3)) : tail)
            else { return nil }
            return h * 100 + t
        }
        return belowHundred(s)
    }

    private static func belowHundred(_ s: String) -> Int? {
        if let v = small[s] ?? tens[s] { return v }
        guard let r = s.range(of: "und"),
              let unit = small[String(s[..<r.lowerBound])], unit < 10,
              let ten = tens[String(s[r.upperBound...])] else { return nil }
        return ten + unit
    }

    /// "zwölften" → 12, "dritten" → 3, "einunddreißigsten" → 31.
    static func ordinal(_ s: String) -> Int? {
        guard let ending = ["en", "er", "em", "es", "e"].first(where: { s.hasSuffix($0) }) else { return nil }
        let stem = String(s.dropLast(ending.count))
        switch stem {
        case "erst": return 1
        case "dritt": return 3
        case "siebt": return 7
        case "acht": return 8
        default: break
        }
        if stem.hasSuffix("st"), let v = cardinal(String(stem.dropLast(2))), v >= 20 { return v }
        // Parakeet also writes "einunddreißigten" for "einunddreißigsten".
        if stem.hasSuffix("t"), let v = cardinal(String(stem.dropLast())), v >= 2 { return v }
        return nil
    }

    static let months: Set<String> = [
        "januar", "jänner", "februar", "märz", "april", "mai", "juni", "juli",
        "august", "september", "oktober", "november", "dezember",
    ]
}

private enum English {
    static let units: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
    ]
    static let teens: [String: Int] = [
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
        "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
    ]
    static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]
    static let ordinals: [String: Int] = [
        "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6, "seventh": 7, "eighth": 8,
        "ninth": 9, "tenth": 10, "eleventh": 11, "twelfth": 12, "thirteenth": 13, "fourteenth": 14,
        "fifteenth": 15, "sixteenth": 16, "seventeenth": 17, "eighteenth": 18, "nineteenth": 19,
        "twentieth": 20, "thirtieth": 30,
    ]
    static let digits: [String: String] = [
        "zero": "0", "oh": "0", "one": "1", "two": "2", "three": "3", "four": "4",
        "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9",
    ]
    static let months: Set<String> = [
        "january", "february", "march", "april", "may", "june", "july",
        "august", "september", "october", "november", "december",
    ]
}

// MARK: - The rules

private struct Formatter {
    var words: [String]
    var gaps: [String]
    /// The language of the sentence each word stands in.
    var language: [SpokenLanguage]

    init(text: String, languages: Set<SpokenLanguage>) {
        let split = Words(text)
        words = split.words
        gaps = split.gaps
        language = Self.sentenceLanguages(words: words, gaps: gaps, languages: languages)
    }

    func run() -> String {
        var out = ""
        var k = 0
        while k < words.count {
            out += gaps[k]
            if let (text, end) = rule(at: k) {
                out += text
                k = end + 1
            } else {
                out += words[k]
                k += 1
            }
        }
        return out + gaps[words.count]
    }

    private func rule(at k: Int) -> (String, Int)? {
        switch language[k] {
        case .german: germanDate(k) ?? germanTime(k) ?? quantity(k) ?? label(k) ?? year(k)
        case .english: englishDate(k) ?? englishTime(k) ?? quantity(k) ?? label(k) ?? year(k)
        }
    }

    // MARK: Helpers

    private func lower(_ k: Int) -> String { words[k].lowercased() }

    /// The word after k, if only a space lies between them.
    private func next(_ k: Int) -> Int? {
        k + 1 < words.count && gaps[k + 1] == " " ? k + 1 : nil
    }

    private func isCapitalized(_ k: Int) -> Bool { words[k].first?.isUppercase == true }

    /// A German noun follows: "sieben Uhr drei Leute" keeps "drei" for the people.
    private func nounFollows(_ k: Int) -> Bool {
        guard language[k] == .german, let n = next(k) else { return false }
        return isCapitalized(n)
    }

    private static func isDigits(_ s: String) -> Bool { s.allSatisfy { $0.isASCII && $0.isWholeNumber } }

    /// Digits as the recogniser wrote them, read the way the language writes them.
    private func written(_ k: Int) -> Amount? {
        let w = words[k]
        guard let first = w.first, first.isWholeNumber else { return nil }
        let (thousands, decimal): (Character, Character) = language[k] == .german ? (".", ",") : (",", ".")
        if Self.isDigits(w), w.count <= 9 { return Amount(integer: Int(w)!, written: w) }
        let groups = w.split(separator: thousands, omittingEmptySubsequences: false)
        if groups.count > 1, groups.allSatisfy({ Self.isDigits(String($0)) }),
           (1 ... 3).contains(groups[0].count), groups.dropFirst().allSatisfy({ $0.count == 3 }),
           let v = Int(groups.joined()) {
            return Amount(integer: v, written: w)
        }
        let parts = w.split(separator: decimal, omittingEmptySubsequences: false)
        if parts.count == 2, Self.isDigits(String(parts[0])), Self.isDigits(String(parts[1])),
           !parts[0].isEmpty, !parts[1].isEmpty, parts[0].count <= 9, let v = Int(parts[0]) {
            return Amount(integer: v, fraction: String(parts[1]), written: w)
        }
        return nil
    }

    /// A whole number spoken in words, which may span several words in English
    /// ("two hundred thousand", "twenty-three"). Returns the last word used.
    private func spoken(_ k: Int) -> (Int, Int)? {
        switch language[k] {
        case .german: German.cardinal(lower(k)).map { ($0, k) }
        case .english: englishCardinal(k)
        }
    }

    private func englishCardinal(_ k: Int) -> (Int, Int)? {
        enum Last { case none, unit, teen, ten, hundred, thousand, and }
        var total = 0, current = 0, last = Last.none
        var best: (Int, Int)?
        var i = k
        scan: while i < words.count {
            let parts = lower(i).split(separator: "-").map(String.init)
            for (p, part) in parts.enumerated() {
                if let v = English.units[part], [.none, .ten, .hundred, .thousand, .and].contains(last) {
                    current += v; last = .unit
                } else if let v = English.teens[part], [.none, .hundred, .thousand, .and].contains(last) {
                    current += v; last = .teen
                } else if let v = English.tens[part], [.none, .hundred, .thousand, .and].contains(last) {
                    current += v; last = .ten
                } else if part == "hundred", [.unit, .teen, .ten].contains(last), current % 100 == current, current > 0 {
                    current *= 100; last = .hundred
                } else if part == "thousand", [.unit, .teen, .ten, .hundred].contains(last), total == 0 {
                    total = current * 1000; current = 0; last = .thousand
                } else if part == "and", parts.count == 1, [.hundred, .thousand].contains(last),
                          let n = next(i), English.units[lower(n)] ?? English.teens[lower(n)] ?? English.tens[lower(n).split(separator: "-").first.map(String.init) ?? ""] != nil {
                    last = .and
                } else {
                    // A word only counts whole: "twenty-twenty-seven" is no single number.
                    if p > 0 { best = nil }
                    break scan
                }
            }
            if last != .and { best = (total + current, i) }
            guard let n = next(i) else { break }
            i = n
        }
        return best
    }

    /// A number with its decimals: "drei Komma fünf", "two point five", "3,80".
    /// `article` lets a lone German "ein" count as 1.
    private func amount(_ k: Int, article: Bool = false) -> (Amount, Int)? {
        if let a = written(k) { return (a, k) }
        if language[k] == .german, lower(k) == "ein", !article { return nil }
        guard let (whole, end) = spoken(k) else { return nil }
        var amount = Amount(integer: whole)
        let point = language[k] == .german ? "komma" : "point"
        if let p = next(end), lower(p) == point, let (fraction, fractionEnd) = fractionDigits(after: p) {
            amount.fraction = fraction
            return (amount, fractionEnd)
        }
        return (amount, end)
    }

    /// "fünf" → "5", "null fünf" → "05", "fünfundzwanzig" → "25".
    private func fractionDigits(after p: Int) -> (String, Int)? {
        let digits = language[p] == .german ? German.digits : English.digits
        var out = "", end = p, i = next(p)
        while let j = i, let d = digits[lower(j)] {
            out += d; end = j; i = next(j)
        }
        if !out.isEmpty { return (out, end) }
        if let j = next(p), let (v, e) = spoken(j), v < 100 { return (String(v), e) }
        return nil
    }

    /// Digits for an amount: a spoken number gets its thousands grouped
    /// ("200.000", "1,250") from five digits up, money from four.
    private func format(_ a: Amount, _ k: Int, group threshold: Int = 10_000, cents: Bool = false) -> String {
        let german = language[k] == .german
        var fraction = a.fraction
        if cents, let f = fraction, f.count == 1 { fraction = f + "0" }
        if let written = a.written, fraction == a.fraction, a.integer < threshold || written.count != String(a.integer).count {
            return written
        }
        var integer = String(a.integer)
        if a.integer >= threshold {
            var grouped = ""
            for (i, c) in integer.reversed().enumerated() {
                if i > 0, i % 3 == 0 { grouped.append(german ? "." : ",") }
                grouped.append(c)
            }
            integer = String(grouped.reversed())
        }
        guard let fraction else { return integer }
        return integer + (german ? "," : ".") + fraction
    }

    // MARK: Money, percent, units

    private static let germanUnits: [String: String] = [
        "kilometer": "km", "kilometern": "km", "km": "km", "meter": "m", "metern": "m",
        "zentimeter": "cm", "zentimetern": "cm", "cm": "cm", "millimeter": "mm", "millimetern": "mm", "mm": "mm",
        "kilogramm": "kg", "kilo": "kg", "kilos": "kg", "kg": "kg", "gramm": "g", "milligramm": "mg",
        "kilobyte": "kB", "kb": "kB", "megabyte": "MB", "mb": "MB", "gigabyte": "GB", "gb": "GB",
        "terabyte": "TB", "tb": "TB",
    ]
    private static let englishUnits: [String: String] = [
        "kilometre": "km", "kilometres": "km", "kilometer": "km", "kilometers": "km", "km": "km",
        "metre": "m", "metres": "m", "meter": "m", "meters": "m",
        "centimetre": "cm", "centimetres": "cm", "centimeter": "cm", "centimeters": "cm", "cm": "cm",
        "millimetre": "mm", "millimetres": "mm", "millimeter": "mm", "millimeters": "mm", "mm": "mm",
        "kilogram": "kg", "kilograms": "kg", "kilo": "kg", "kilos": "kg", "kg": "kg", "gram": "g", "grams": "g",
        "kilobyte": "kB", "kilobytes": "kB", "kb": "kB", "megabyte": "MB", "megabytes": "MB", "mb": "MB",
        "gigabyte": "GB", "gigabytes": "GB", "gb": "GB", "terabyte": "TB", "terabytes": "TB", "tb": "TB",
    ]
    /// Units that keep their word; only the number becomes digits.
    private static let germanCounted: Set<String> = ["zoll", "grad", "liter", "litern", "cent"]
    private static let englishCounted: Set<String> = [
        "inch", "inches", "mile", "miles", "foot", "feet", "degree", "degrees", "litre", "litres", "liter", "liters", "cents",
    ]
    private static let scales: Set<String> = ["million", "millionen", "milliarde", "milliarden", "billion", "billions", "millions"]

    private func quantity(_ k: Int) -> (String, Int)? {
        guard let (a, end) = amount(k), let u = next(end) else { return nil }
        let german = language[k] == .german
        let unit = lower(u)

        // "4,5 Millionen Euro", "$1.5 million"
        if Self.scales.contains(unit), let c = next(u), let symbol = currency(c) {
            let number = format(a, k)
            return german ? ("\(number) \(words[u]) \(words[c])", c) : ("\(symbol)\(number) \(words[u])", c)
        }
        if let symbol = currency(u) {
            var a = a, last = u
            if a.isWhole, let (cents, centsEnd) = cents(after: u) {
                a.fraction = cents; a.written = nil; last = centsEnd
            }
            let number = format(a, k, group: 1000, cents: true)
            if german { return ("\(number) \(symbol == "€" ? "€" : words[u])", last) }
            return ("\(symbol)\(number)", last)
        }
        if german ? unit == "prozent" : unit == "percent" {
            return ("\(format(a, k))\(german ? " %" : "%")", u)
        }
        if !german, unit == "per", let c = next(u), lower(c) == "cent" {
            return ("\(format(a, k))%", c)
        }
        if let symbol = (german ? Self.germanUnits : Self.englishUnits)[unit] {
            return ("\(format(a, k)) \(symbol)", u)
        }
        if (german ? Self.germanCounted : Self.englishCounted).contains(unit), a.written == nil {
            return ("\(format(a, k)) \(words[u])", u)
        }
        return nil
    }

    /// The sign an amount is written with in English; German writes € and keeps "Dollar".
    private func currency(_ k: Int) -> String? {
        switch lower(k) {
        case "euro", "euros": "€"
        case "dollar", "dollars": "$"
        default: nil
        }
    }

    /// "Euro fünfzig", "euros and fifty cents", "Euro und fünfzig Cent".
    private func cents(after u: Int) -> (String, Int)? {
        guard var n = next(u) else { return nil }
        let joined = lower(n) == "und" || lower(n) == "and"
        if joined { guard let m = next(n) else { return nil }; n = m }
        guard let (c, end) = amount(n), c.isWhole, (1 ... 99).contains(c.integer), c.written == nil || joined else { return nil }
        let digits = c.integer < 10 ? "0\(c.integer)" : String(c.integer)
        if let w = next(end), lower(w) == "cent" || lower(w) == "cents" { return (digits, w) }
        if joined || nounFollows(end) { return nil }
        return (digits, end)
    }

    // MARK: Times

    /// "vierzehn Uhr dreißig" → "14:30 Uhr", "neun Uhr" → "9 Uhr", "14.30 Uhr" → "14:30 Uhr".
    private func germanTime(_ k: Int) -> (String, Int)? {
        if let u = next(k), lower(u) == "uhr", let clock = writtenClock(words[k]) {
            return ("\(clock) Uhr", u)
        }
        guard let (h, end) = amount(k, article: true), h.isWhole, (0 ... 24).contains(h.integer),
              let u = next(end), lower(u) == "uhr" else { return nil }
        if let m = next(u), !nounFollows(m), let (minute, mEnd) = amount(m), minute.isWhole, minute.written == nil,
           (0 ... 59).contains(minute.integer) {
            return ("\(h.integer):\(minute.integer < 10 ? "0" : "")\(minute.integer) Uhr", mEnd)
        }
        return ("\(h.integer) Uhr", u)
    }

    /// "14.30" or "14:30" as the recogniser wrote it.
    private func writtenClock(_ w: String) -> String? {
        let parts = w.split(whereSeparator: { $0 == "." || $0 == ":" })
        guard parts.count == 2, parts[1].count == 2, (1 ... 2).contains(parts[0].count),
              let h = Int(parts[0]), let m = Int(parts[1]), h <= 24, m <= 59 else { return nil }
        return "\(h):\(parts[1])"
    }

    /// "two thirty p.m." → "2:30 pm", "nine a.m." → "9 am".
    private func englishTime(_ k: Int) -> (String, Int)? {
        var clock: String
        var end: Int
        if let c = writtenClock(words[k]), words[k].contains(":") {
            clock = c; end = k
        } else {
            guard let (h, hEnd) = amount(k), h.isWhole, h.written == nil || Self.isDigits(words[k]),
                  (1 ... 12).contains(h.integer) else { return nil }
            clock = String(h.integer); end = hEnd
            if let m = next(hEnd), lower(m) == "oh", let d = next(m), let v = English.units[lower(d)] {
                clock += ":0\(v)"; end = d
            } else if let m = next(hEnd), let (minute, mEnd) = amount(m), minute.isWhole, minute.written == nil,
                      (10 ... 59).contains(minute.integer), let after = next(mEnd), meridiem(after) != nil {
                clock += ":\(minute.integer)"; end = mEnd
            }
        }
        guard let p = next(end), let suffix = meridiem(p) else { return nil }
        // "p.m." at the end of a sentence also ended it.
        let endsSentence = words[p].hasSuffix(".")
            && (p + 1 == words.count ? gaps[p + 1].isEmpty || gaps[p + 1].hasPrefix("\n")
                : gaps[p + 1] == " " && isCapitalized(p + 1))
        return ("\(clock) \(suffix)\(endsSentence ? "." : "")", p)
    }

    private func meridiem(_ k: Int) -> String? {
        switch words[k] {
        case "a.m.", "A.M.", "am", "AM": "am"
        case "p.m.", "P.M.", "pm", "PM": "pm"
        default: nil
        }
    }

    // MARK: Dates

    /// "am zwölften Oktober" → "am 12. Oktober", "vom dritten bis fünften März"
    /// → "vom 3. bis 5. März", and a spoken year after the month.
    private func germanDate(_ k: Int) -> (String, Int)? {
        if isMonth(k), let (y, end) = spokenYear(after: k) { return ("\(words[k]) \(y)", end) }
        guard let first = German.ordinal(lower(k)), (1 ... 31).contains(first) else { return nil }
        var out = "\(first)."
        var i = k
        for _ in 0 ..< 4 {
            guard let n = next(i) else { return nil }
            if isMonth(n) {
                out += " " + words[n]
                if let (y, end) = spokenYear(after: n) { return (out + " " + y, end) }
                return (out, n)
            }
            // "bis", "bis zum", "und", "oder" between two days.
            var j = n, joiners: [String] = []
            while ["bis", "zum", "und", "oder"].contains(lower(j)), joiners.count < 2, let m = next(j) {
                joiners.append(words[j]); j = m
            }
            guard !joiners.isEmpty, let day = German.ordinal(lower(j)), (1 ... 31).contains(day) else { return nil }
            out += " " + joiners.joined(separator: " ") + " \(day)."
            i = j
        }
        return nil
    }

    /// "October twelfth" → "October 12", "December thirty-first, twenty twenty-seven" → "December 31, 2027".
    private func englishDate(_ k: Int) -> (String, Int)? {
        guard isMonth(k), let d = next(k) else { return nil }
        if let (y, end) = spokenYear(after: k) { return ("\(words[k]) \(y)", end) }
        guard let (day, dEnd) = englishOrdinal(d) ?? spoken(d), (1 ... 31).contains(day) else { return nil }
        let date = "\(words[k]) \(day)"
        let gap = dEnd + 1 < words.count ? gaps[dEnd + 1] : ""
        if gap == " " || gap == ", ", let (y, end) = year(at: dEnd + 1) { return ("\(date), \(y)", end) }
        return (date, dEnd)
    }

    private func englishOrdinal(_ k: Int) -> (Int, Int)? {
        let parts = lower(k).split(separator: "-").map(String.init)
        if parts.count == 1, let v = English.ordinals[parts[0]] { return (v, k) }
        if parts.count == 2, let t = English.tens[parts[0]], let u = English.ordinals[parts[1]], u < 10 { return (t + u, k) }
        if parts.count == 1, let t = English.tens[parts[0]], let n = next(k), let u = English.ordinals[lower(n)], u < 10 {
            return (t + u, n)
        }
        return nil
    }

    private func isMonth(_ k: Int) -> Bool {
        isCapitalized(k) && (language[k] == .german ? German.months : English.months).contains(lower(k))
    }

    private func spokenYear(after k: Int) -> (String, Int)? {
        next(k).flatMap(year(at:))
    }

    /// A spoken year: "zweitausendsiebenundzwanzig", "two thousand twenty-seven",
    /// "twenty twenty-seven", "nineteen ninety-nine".
    private func year(at k: Int) -> (String, Int)? {
        guard written(k) == nil else { return nil }
        if let (v, end) = spoken(k), (1000 ... 2999).contains(v) { return (String(v), end) }
        guard language[k] == .english else { return nil }
        let parts = lower(k).split(separator: "-").map(String.init)
        // "twenty-twenty-seven" as one word, as Parakeet sometimes writes it.
        if parts.count >= 2, let century = English.teens[parts[0]] ?? English.tens[parts[0]], century >= 10,
           let rest = englishTwoDigits(Array(parts.dropFirst())) {
            return (String(century * 100 + rest), k)
        }
        guard parts.count == 1, let century = English.teens[parts[0]] ?? English.tens[parts[0]],
              let n = next(k) else { return nil }
        let restParts = lower(n).split(separator: "-").map(String.init)
        if let rest = englishTwoDigits(restParts) { return (String(century * 100 + rest), n) }
        // "twenty twenty seven"
        if restParts.count == 1, let t = English.tens[restParts[0]], let m = next(n), let u = English.units[lower(m)] {
            return (String(century * 100 + t + u), m)
        }
        return nil
    }

    private func englishTwoDigits(_ parts: [String]) -> Int? {
        if parts.count == 1 { return English.teens[parts[0]] ?? English.tens[parts[0]] }
        if parts.count == 2, let t = English.tens[parts[0]], let u = English.units[parts[1]] { return t + u }
        return nil
    }

    /// "im Jahr neunzehnhundertneunundneunzig" → "im Jahr 1999".
    private func year(_ k: Int) -> (String, Int)? {
        guard ["jahr", "jahre", "jahres", "year"].contains(lower(k)), let (y, end) = spokenYear(after: k) else { return nil }
        return ("\(words[k]) \(y)", end)
    }

    // MARK: Version and page numbers

    /// "Version zwei Punkt vier" → "Version 2.4", "page seventeen" → "page 17".
    private func label(_ k: Int) -> (String, Int)? {
        let word = lower(k)
        let isVersion = word == "version"
        guard isVersion || (language[k] == .german ? ["seite", "kapitel"] : ["page", "chapter"]).contains(word),
              let n = next(k), let (first, end) = number(n) else { return nil }
        var out = first, last = end
        let points: Set<String> = language[k] == .german ? ["punkt", "komma"] : ["point", "dot"]
        while isVersion, let p = next(last), points.contains(lower(p)), let m = next(p), let (part, e) = number(m) {
            out += "." + part; last = e
        }
        guard out != words[n] || last != n else { return nil }
        return ("\(words[k]) \(out)", last)
    }

    /// A whole number for a label, written or spoken.
    private func number(_ k: Int) -> (String, Int)? {
        if Self.isDigits(words[k]) { return (words[k], k) }
        if language[k] == .german, lower(k) == "ein" { return nil }
        return spoken(k).map { (String($0.0), $0.1) }
    }

    // MARK: Language per sentence

    private static let germanWords: Set<String> = [
        "der", "die", "das", "und", "ist", "ich", "wir", "nicht", "mit", "für", "auf", "ein", "eine", "zu",
        "den", "dem", "im", "am", "um", "bei", "von", "sich", "es", "sie", "du", "bitte", "liegt", "kostet",
        "sind", "hat", "haben", "bis", "seit", "vom", "zum", "uns", "noch", "auch", "dass", "wie", "ab",
    ]
    private static let englishWords: Set<String> = [
        "the", "and", "is", "i", "we", "not", "with", "for", "on", "a", "an", "to", "of", "in", "at", "it",
        "you", "this", "that", "are", "was", "has", "have", "by", "from", "until", "let's", "our", "be", "will",
    ]

    /// Dictating both languages: each sentence counts as the one more of
    /// its small words belong to; a tie counts as German.
    private static func sentenceLanguages(words: [String], gaps: [String], languages: Set<SpokenLanguage>) -> [SpokenLanguage] {
        if languages.count == 1 { return Array(repeating: languages.first!, count: words.count) }
        var out = [SpokenLanguage](repeating: .german, count: words.count)
        var start = 0
        for k in 0 ... words.count {
            let ends = k == words.count
                || (k > 0 && gaps[k].contains(where: { "!?\n".contains($0) }))
                || (k > 0 && gaps[k].contains(".") && !(words[k - 1].last?.isWholeNumber ?? false))
            guard ends, k > start else { continue }
            var german = 0, english = 0
            for w in words[start ..< k] {
                let w = w.lowercased()
                if germanWords.contains(w) { german += 1 }
                if englishWords.contains(w) { english += 1 }
            }
            let language: SpokenLanguage = english > german ? .english : .german
            for i in start ..< k { out[i] = language }
            start = k
        }
        return out
    }
}
