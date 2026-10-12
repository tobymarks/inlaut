import Foundation
import FoundationModels
import os

/// Asks the language model that comes with macOS (Apple Intelligence) whether
/// a possible self-correction is one. `SystemLanguageModel` runs on this Mac;
/// the Private Cloud Compute model is a separate class and is never used.
/// The model answers true or false and writes no text of its own.
@MainActor
enum CorrectionJudge {
    private static let log = Logger(subsystem: "de.tobymarks.inlaut", category: "polish")
    /// Checking a transformation of the user's own words, so the guardrails
    /// meant for generated content would only get in the way of blunt language.
    private static let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
    private static var warm: LanguageModelSession?
    /// Longer than this and the dictation is pasted as it is.
    private static let patience: Duration = .seconds(3)

    static var isAvailable: Bool { model.availability == .available }

    /// Why the model cannot be used, in words for the settings.
    static var unavailableReason: String? {
        switch model.availability {
        case .available: nil
        case .unavailable(.appleIntelligenceNotEnabled): String(localized: "Needs Apple Intelligence, which is turned off in System Settings.")
        case .unavailable(.modelNotReady): String(localized: "Apple Intelligence is still preparing its model.")
        case .unavailable: String(localized: "Needs Apple Intelligence, which this Mac does not offer.")
        }
    }

    @Generable
    struct Verdict {
        @Guide(description: "One short sentence: what does the speaker do after the correction word?")
        var reason: String
        @Guide(description: "true if the speaker took words back and replaced them, false if the sentence simply continues")
        var corrected: Bool
    }

    private static let instructions = """
        You judge dictated sentences. While speaking, people sometimes take back words and say them again differently, after a word like nein, nee, ich meine, I mean, no, sorry.
        You get the sentence as spoken and a shorter version without the words that may have been taken back.
        Answer true if the speaker replaced the earlier words with the later ones, so that the shorter version is what they meant to say and nothing they meant is lost.
        Answer false if the sentence simply continues, if the later words add to the earlier ones instead of replacing them, or if the shorter version loses information or is not a correct sentence.

        Examples:
        Spoken: Wir treffen uns am Montag, nein, am Dienstag.
        Shorter: Wir treffen uns am Dienstag.
        true (Dienstag replaces Montag)

        Spoken: Das war nicht gut, nein, das war sogar richtig schlecht.
        Shorter: Das war nicht das war sogar richtig schlecht.
        false (the speaker adds to it, nothing is taken back)

        Spoken: Send it to John, I mean to Jane.
        Shorter: Send it to Jane.
        true (Jane replaces John)

        Spoken: I asked him, no, he would rather stay.
        Shorter: I asked he would rather stay.
        false (the "no" is part of what is told)
        """

    private static func session() -> LanguageModelSession {
        LanguageModelSession(model: model, instructions: instructions)
    }

    /// Loads the model while the user is still speaking.
    static func prewarm() {
        guard isAvailable, warm == nil else { return }
        let session = session()
        session.prewarm()
        warm = session
    }

    static func confirm(_ correction: TextPolish.Correction) async -> Bool {
        guard isAvailable else { return false }
        let session = warm ?? session()
        warm = nil
        let started = Date()
        let prompt = "Spoken: \(correction.spoken.trimmingCharacters(in: .whitespacesAndNewlines))\nShorter: \(correction.shorter.trimmingCharacters(in: .whitespacesAndNewlines))"
        let verdict: Bool? = await withTaskGroup(of: Bool?.self) { group in
            group.addTask {
                try? await session.respond(to: prompt, generating: Verdict.self,
                                           options: GenerationOptions(samplingMode: .greedy)).content.corrected
            }
            group.addTask {
                try? await Task.sleep(for: patience)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        // Lengths and timing only — the dictated text is never logged.
        log.notice("correction: \(correction.spoken.count) chars, \(verdict.map { $0 ? "taken" : "left" } ?? "no answer", privacy: .public) in \(Date().timeIntervalSince(started), format: .fixed(precision: 2))s")
        return verdict ?? false
    }
}
