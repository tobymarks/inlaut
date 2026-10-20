import AppKit
import SwiftUI

/// How dictations into one app differ from the rest (#17), keyed by bundle
/// ID. A terminal or a chat wants no full stop at the end and no capital
/// letter at the start; everything else keeps the normal formatting.
struct AppRule: Codable, Hashable, Identifiable {
    var bundleID: String
    var name: String
    var noTrailingPeriod = true
    var noCapitalStart = true
    var id: String { bundleID }

    /// The last step of a dictation. Snippets never get here: they are
    /// inserted as written.
    func apply(to text: String) -> String {
        var text = text
        if noTrailingPeriod { text = Self.droppingTrailingPeriod(text) }
        if noCapitalStart { text = Self.lowercasingStart(text) }
        return text
    }

    /// One final "." goes, also before line breaks said at the end; "…",
    /// "...", "?" and "!" stay.
    static func droppingTrailingPeriod(_ text: String) -> String {
        guard let last = text.lastIndex(where: { !$0.isWhitespace }), text[last] == "." else { return text }
        if last > text.startIndex, ".".contains(text[text.index(before: last)]) { return text }
        return String(text[..<last]) + text[text.index(after: last)...]
    }

    /// The first word in lower case, unless it is written like a name of
    /// its own: "DAM", "iPhone", "McKinsey", "I", "I'm".
    static func lowercasingStart(_ text: String) -> String {
        guard let start = text.firstIndex(where: { !$0.isWhitespace }), text[start].isUppercase else { return text }
        let word = text[start...].prefix { $0.isLetter || $0 == "'" || $0 == "’" }
        let letters = word.filter(\.isLetter)
        if letters.dropFirst().contains(where: \.isUppercase) { return text }
        if word.prefix(while: \.isLetter) == "I" { return text }
        return String(text[..<start]) + text[start].lowercased() + text[text.index(after: start)...]
    }
}

extension [AppRule] {
    func rule(for bundleID: String?) -> AppRule? {
        guard let bundleID else { return nil }
        return first { $0.bundleID == bundleID }
    }
}

/// The apps with their own rules, and a menu to add one.
struct AppRulesField: View {
    @Binding var rules: [AppRule]

    var body: some View {
        ForEach($rules) { $rule in
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(nsImage: Self.icon(for: rule.bundleID))
                        .resizable()
                        .frame(width: 20, height: 20)
                        .accessibilityHidden(true)
                    Text(rule.name)
                    Spacer()
                    Button {
                        rules.removeAll { $0.id == rule.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("Remove \(rule.name)"))
                }
                Toggle("No full stop at the end", isOn: $rule.noTrailingPeriod)
                    .padding(.leading, 28)
                Toggle("No capital letter at the start", isOn: $rule.noCapitalStart)
                    .padding(.leading, 28)
            }
            .padding(.vertical, 2)
        }
        Menu("Add App …") {
            ForEach(Self.runningApps(excluding: Set(rules.map(\.bundleID))), id: \.bundleID) { app in
                Button(app.name) { add(app) }
            }
            Divider()
            Button("Choose …") { choose() }
        }
        .fixedSize()
    }

    private func add(_ app: (bundleID: String, name: String)) {
        guard !rules.contains(where: { $0.bundleID == app.bundleID }) else { return }
        rules.append(AppRule(bundleID: app.bundleID, name: app.name))
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url,
              let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { return }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        add((bundleID, name))
    }

    /// Apps with a window that are running now, without inlaut itself.
    private static func runningApps(excluding taken: Set<String>) -> [(bundleID: String, name: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in
                guard let id = app.bundleIdentifier, id != Bundle.main.bundleIdentifier, !taken.contains(id) else { return nil }
                return (id, app.localizedName ?? id)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func icon(for bundleID: String) -> NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
