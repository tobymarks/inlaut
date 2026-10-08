import Foundation
import SwiftUI

/// "What the recogniser writes" → "what you want". Applied after every
/// dictation, whole words only, ignoring case.
struct Replacement: Codable, Hashable, Identifiable {
    var from: String
    var to: String
    var id: String { from.lowercased() }
}

extension [Replacement] {
    func apply(to text: String) -> String {
        // Longer phrases first, so "Meyle und Müller" wins over "Müller".
        sorted { $0.from.count > $1.from.count }.reduce(text) { text, rule in
            let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: rule.from) + "(?![\\p{L}\\p{N}])"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
            return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text),
                                                  withTemplate: NSRegularExpression.escapedTemplate(for: rule.to))
        }
    }
}

/// Rules as removable bubbles plus a "from → to" input row.
struct ReplacementsField: View {
    @Binding var rules: [Replacement]
    @State private var from = ""
    @State private var to = ""
    @FocusState private var fromFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !rules.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(rules) { rule in
                        Bubble(text: "\(rule.from) → \(rule.to.isEmpty ? "∅" : rule.to)") {
                            rules.removeAll { $0.id == rule.id }
                        }
                    }
                }
            }
            HStack(spacing: 6) {
                TextField("erkannt, z. B. Dum", text: $from)
                    .focused($fromFocused)
                    .onSubmit(add)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                TextField("geschrieben, z. B. DAM", text: $to)
                    .onSubmit(add)
                Button(action: add) { Image(systemName: "plus") }
                    .disabled(from.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .textFieldStyle(.roundedBorder)
        }
        .padding(.vertical, 4)
    }

    private func add() {
        let rule = Replacement(from: from.trimmingCharacters(in: .whitespaces), to: to.trimmingCharacters(in: .whitespaces))
        guard !rule.from.isEmpty else { return }
        rules.removeAll { $0.id == rule.id }
        rules.append(rule)
        from = ""
        to = ""
        fromFocused = true
    }
}

private struct Bubble: View {
    let text: String
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            Text(text).lineLimit(1)
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(hovering ? .primary : .secondary)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help("Entfernen")
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 4)
        .background(Color.inlautAccent.opacity(0.12), in: .capsule)
    }
}

/// Lays children out left to right and wraps into new rows.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows = [Row()]
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}
