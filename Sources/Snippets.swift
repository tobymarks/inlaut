import Foundation
import SwiftUI

/// A stored text behind a spoken phrase: "meine Signatur" → a sign-off of
/// several lines. Unlike a replacement it only fires when the phrase is the
/// whole dictation, so a paragraph never lands in the middle of a sentence.
struct Snippet: Codable, Hashable, Identifiable {
    var phrase: String
    var text: String
    var id: String { Self.key(phrase) }

    /// What is compared: the words only, so "Meine Signatur." (as the
    /// recogniser writes it) matches "meine signatur", and ss matches ß.
    static func key(_ spoken: String) -> String {
        spoken.lowercased()
            .replacingOccurrences(of: "ß", with: "ss")
            .split { !$0.isLetter && !$0.isNumber }
            .joined(separator: " ")
    }

    /// The first line that says something, with a mark when more follows.
    var preview: String {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let first = lines.first else { return "" }
        return lines.count > 1 ? first + " …" : first
    }
}

extension [Snippet] {
    func match(_ dictation: String) -> String? {
        let key = Snippet.key(dictation)
        guard !key.isEmpty else { return nil }
        return first { $0.id == key }?.text
    }
}

/// Replacements and snippets as one file, to back them up or move them to
/// another Mac.
struct TextRulesFile: Codable {
    var replacements: [Replacement] = []
    var snippets: [Snippet] = []

    init(replacements: [Replacement], snippets: [Snippet]) {
        self.replacements = replacements
        self.snippets = snippets
    }

    /// Either list may be missing, so a file with only replacements loads.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        replacements = try container.decodeIfPresent([Replacement].self, forKey: .replacements) ?? []
        snippets = try container.decodeIfPresent([Snippet].self, forKey: .snippets) ?? []
        if !container.contains(.replacements), !container.contains(.snippets) {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "neither replacements nor snippets"))
        }
    }

    var data: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)) ?? Data()
    }

    /// Adds the file's entries to the given lists; an entry for the same
    /// word or phrase replaces the existing one. Empty entries are dropped.
    func merge(into replacements: inout [Replacement], _ snippets: inout [Snippet]) {
        for rule in self.replacements where !rule.id.isEmpty {
            replacements.removeAll { $0.id == rule.id }
            replacements.append(rule)
        }
        for snippet in self.snippets where !snippet.id.isEmpty && !snippet.text.isEmpty {
            snippets.removeAll { $0.id == snippet.id }
            snippets.append(snippet)
        }
    }
}

/// Snippets as rows with the phrase and the first line, plus a sheet to
/// write or change one.
struct SnippetsField: View {
    @Binding var snippets: [Snippet]
    @State private var editing: Draft?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(snippets) { snippet in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snippet.phrase)
                        Text(snippet.preview)
                            .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button("Edit …") { editing = Draft(original: snippet.id, phrase: snippet.phrase, text: snippet.text) }
                    Button { snippets.removeAll { $0.id == snippet.id } } label: { Image(systemName: "trash") }
                        .help("Remove")
                }
            }
            Button("Add Snippet …") { editing = Draft() }
        }
        .padding(.vertical, 4)
        .sheet(item: $editing) { draft in
            SnippetEditor(draft: draft) { snippet in
                // A changed phrase replaces the old entry, and any other with the new phrase.
                let index = snippets.firstIndex { $0.id == draft.original }
                snippets.removeAll { $0.id == draft.original || $0.id == snippet.id }
                snippets.insert(snippet, at: min(index ?? snippets.count, snippets.count))
            }
        }
    }

    struct Draft: Identifiable {
        let id = UUID()
        var original: String?
        var phrase = ""
        var text = ""
    }
}

struct SnippetEditor: View {
    @State var draft: SnippetsField.Draft
    let save: (Snippet) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var phraseFocused: Bool

    private var snippet: Snippet? {
        let snippet = Snippet(phrase: draft.phrase.trimmingCharacters(in: .whitespacesAndNewlines),
                              text: draft.text.trimmingCharacters(in: .whitespacesAndNewlines))
        return snippet.id.isEmpty || snippet.text.isEmpty ? nil : snippet
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("What you say")
                TextField("e.g. my signature", text: $draft.phrase)
                    .textFieldStyle(.roundedBorder)
                    .focused($phraseFocused)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("What inlaut writes")
                TextEditor(text: $draft.text)
                    .font(.body)
                    .frame(height: 160)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
            }
            Text("Say the phrase on its own, without anything else in the same dictation.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    if let snippet { save(snippet) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(snippet == nil)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear { phraseFocused = draft.original == nil }
    }
}
