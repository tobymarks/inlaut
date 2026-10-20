import XCTest

/// Runs TestData/text-pipeline.json, which windows/tests/Inlaut.CoreSmoke runs
/// as well, so every difference the cases find between the Mac and Windows
/// text handling is one the file names. Both runners check the file the same
/// way, so a misspelt key cannot quietly turn a case into a weaker one.
final class TextPipelineCorpusTests: XCTestCase {
    private static let shared: Set<String> = ["id", "step", "input", "expected", "mac", "windows", "differences"]
    private static let stepKeys: [String: Set<String>] = [
        "sharpS": [],
        "voiceCommands": ["languages"],
        "dictation": ["languages", "voiceCommands", "sharpS", "replacements", "snippets"],
    ]

    func testSharedCases() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("TestData/text-pipeline.json")
        let corpus = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertEqual(Set(corpus.keys), ["about", "differences", "cases"])
        let differences = try XCTUnwrap(corpus["differences"] as? [String: String])
        let cases = try XCTUnwrap(corpus["cases"] as? [[String: Any]])
        XCTAssertFalse(cases.isEmpty)

        var ids = Set<String>()
        var used = Set<String>()
        for item in cases {
            let id = try XCTUnwrap(item["id"] as? String, "a case has no id")
            XCTAssertTrue(ids.insert(id).inserted, "\(id): id is not unique")
            let step = item["step"] as? String ?? "dictation"
            guard let keys = Self.stepKeys[step] else {
                XCTFail("\(id): unknown step \(step)")
                continue
            }
            let extra = Set(item.keys).subtracting(Self.shared).subtracting(keys)
            XCTAssert(extra.isEmpty, "\(id): \(extra.sorted()) do not belong to step \(step)")
            if step != "sharpS" { XCTAssertNotNil(item["languages"], "\(id): needs languages") }

            let expected: String
            if let both = item["expected"] as? String {
                XCTAssert(item["mac"] == nil && item["windows"] == nil && item["differences"] == nil,
                          "\(id): expected holds on both platforms, so it needs no mac, windows or differences")
                expected = both
            } else {
                guard let mac = item["mac"] as? String, let windows = item["windows"] as? String,
                      let named = item["differences"] as? [String], !named.isEmpty else {
                    XCTFail("\(id): needs expected, or mac, windows and differences")
                    continue
                }
                XCTAssertNotEqual(mac, windows, "\(id): mac and windows agree, so this is expected")
                for key in named where differences[key] == nil { XCTFail("\(id): unknown difference \(key)") }
                used.formUnion(named)
                expected = mac
            }
            XCTAssertEqual(try run(item, id: id, step: step), expected, id)
        }
        XCTAssertEqual(used, Set(differences.keys), "every named difference needs a case")
    }

    private func run(_ item: [String: Any], id: String, step: String) throws -> String {
        let input = try XCTUnwrap(item["input"] as? String, "\(id): needs input")
        let languages = Set(try (item["languages"] as? [String] ?? []).map { name in
            try XCTUnwrap(SpokenLanguage(rawValue: name), "\(id): unknown language \(name)")
        })
        switch step {
        case "sharpS":
            return SharpS.apply(to: input)
        case "voiceCommands":
            return VoiceCommands.apply(to: input, languages: languages)
        default:
            let replacements = try rules(item["replacements"], id: id, keys: ["from", "to"])
                .map { Replacement(from: $0["from"] ?? "", to: $0["to"] ?? "") }
            let snippets = try rules(item["snippets"], id: id, keys: ["phrase", "text"])
                .map { Snippet(phrase: $0["phrase"] ?? "", text: $0["text"] ?? "") }
            let pipeline = TextPipeline(languages: languages,
                                        voiceCommands: try flag(item["voiceCommands"], id: id),
                                        sharpS: try flag(item["sharpS"], id: id),
                                        replacements: replacements,
                                        snippets: snippets)
            return pipeline.dictation(input)
        }
    }

    private func flag(_ value: Any?, id: String) throws -> Bool {
        guard let value else { return true }
        return try XCTUnwrap(value as? Bool, "\(id): voiceCommands and sharpS are true or false")
    }

    private func rules(_ value: Any?, id: String, keys: Set<String>) throws -> [[String: String]] {
        guard let value else { return [] }
        let list = try XCTUnwrap(value as? [[String: String]], "\(id): rules are objects of strings")
        for rule in list { XCTAssertEqual(Set(rule.keys), keys, "\(id): a rule has exactly \(keys.sorted())") }
        return list
    }
}
