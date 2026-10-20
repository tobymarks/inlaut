import AppKit
import AVFoundation
import CoreAudio
import XCTest

@MainActor
final class TextInserterTests: XCTestCase {
    private func environment(_ pasteboard: NSPasteboard) -> TextInserter.Environment {
        .init(isTrusted: { true }, targetUnchanged: { true }, waitForModifiers: { true },
              postPaste: { true }, waitForPaste: {})
    }

    func testRestoresEmptyClipboard() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.clearContents()
        let result = try await TextInserter.insert("Diktat", pasteboard: board, environment: environment(board))
        XCTAssertEqual(result, .inserted)
        XCTAssertNil(board.string(forType: .string))
    }

    func testPreservesCopyDuringModifierWait() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("Vorher", forType: .string)
        var env = environment(board)
        env.waitForModifiers = {
            board.clearContents()
            board.setString("Während des Wartens kopiert", forType: .string)
            return true
        }
        env.postPaste = {
            XCTAssertEqual(board.string(forType: .string), "Diktat")
            return true
        }
        _ = try await TextInserter.insert("Diktat", pasteboard: board, environment: env)
        XCTAssertEqual(board.string(forType: .string), "Während des Wartens kopiert")
    }

    func testNewCopyAfterPasteWins() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("Vorher", forType: .string)
        var env = environment(board)
        env.waitForPaste = {
            board.clearContents()
            board.setString("Neue Kopie", forType: .string)
        }
        _ = try await TextInserter.insert("Diktat", pasteboard: board, environment: env)
        XCTAssertEqual(board.string(forType: .string), "Neue Kopie")
    }

    func testSpokenBreaksAtTheEdgesReachTheField() async throws {
        // A dictation that starts or ends with a voice command breaks the line
        // next to the cursor (#20); here pasted into an AppKit text view.
        let pipeline = TextPipeline(languages: [.german])
        for (before, spoken, after) in [
            ("Erster Absatz.", "neuer Absatz das ist der zweite Absatz.", "Erster Absatz.\n\nDas ist der zweite Absatz."),
            ("Erster Absatz.", "neue Zeile", "Erster Absatz.\n"),
            ("", "Hier endet die erste Zeile neuer Absatz", "Hier endet die erste Zeile\n\n"),
        ] {
            let board = NSPasteboard.withUniqueName()
            defer { board.releaseGlobally() }
            let field = NSTextView()
            field.string = before
            field.setSelectedRange(NSRange(location: (before as NSString).length, length: 0))
            var env = environment(board)
            env.postPaste = { field.readSelection(from: board, type: .string) }
            let result = try await TextInserter.insert(pipeline.dictation(spoken), pasteboard: board, environment: env)
            XCTAssertEqual(result, .inserted)
            XCTAssertEqual(field.string, after, spoken)
        }
    }

    func testChangedTargetDoesNotPaste() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        var env = environment(board)
        env.targetUnchanged = { false }
        env.postPaste = { XCTFail("Must not paste into another field"); return true }
        let result = try await TextInserter.insert("Diktat", pasteboard: board, environment: env)
        XCTAssertEqual(result, .copied("Text field changed – paste the dictation with ⌘V"))
        XCTAssertEqual(board.string(forType: .string), "Diktat")
    }

    func testHeldModifiersDoNotPaste() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        var env = environment(board)
        env.waitForModifiers = { false }
        env.postPaste = { XCTFail("Must not post a modified shortcut"); return true }
        _ = try await TextInserter.insert("Diktat", pasteboard: board, environment: env)
        XCTAssertEqual(board.string(forType: .string), "Diktat")
    }

    func testMissingPermissionCopiesOnly() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        var env = environment(board)
        env.isTrusted = { false }
        env.postPaste = { XCTFail("Missing accessibility permission"); return true }
        _ = try await TextInserter.insert("Diktat", pasteboard: board, environment: env)
        XCTAssertEqual(board.string(forType: .string), "Diktat")
    }

    func testCancellationRestoresRichClipboard() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let rich = NSPasteboardItem()
        rich.setString("Vorher", forType: .string)
        rich.setData(Data([1, 2, 3]), forType: .rtf)
        board.writeObjects([rich])
        var env = environment(board)
        env.waitForPaste = { throw CancellationError() }
        do {
            _ = try await TextInserter.insert("Diktat", pasteboard: board, environment: env)
            XCTFail("Expected cancellation")
        } catch is CancellationError { }
        XCTAssertEqual(board.string(forType: .string), "Vorher")
        XCTAssertEqual(board.data(forType: .rtf), Data([1, 2, 3]))
    }

    func testCancellationBeforePasteLeavesClipboardAlone() async throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        board.setString("Vorher", forType: .string)
        var env = environment(board)
        env.waitForModifiers = { throw CancellationError() }
        env.postPaste = { XCTFail("Cancelled insertion must not paste"); return true }
        do {
            _ = try await TextInserter.insert("Diktat", pasteboard: board, environment: env)
            XCTFail("Expected cancellation")
        } catch is CancellationError { }
        XCTAssertEqual(board.string(forType: .string), "Vorher")
    }
}

final class TextProcessingTests: XCTestCase {
    func testReplacementWordBoundariesAndLiteralCharacters() {
        let rules = [Replacement(from: "Dum", to: "DAM"), Replacement(from: "Preis", to: "$5\\Stück")]
        XCTAssertEqual(rules.apply(to: "Dum, Dummer und dum. Preis!"), "DAM, Dummer und DAM. $5\\Stück!")
    }

    func testLongerReplacementWins() {
        let rules = [Replacement(from: "Müller", to: "Miller"), Replacement(from: "Meyle und Müller", to: "Firma")]
        XCTAssertEqual(rules.apply(to: "Meyle und Müller und Müller"), "Firma und Miller")
    }

    func testSnippetNeedsThePhraseOnItsOwn() {
        let snippets = [Snippet(phrase: "meine Grüße", text: "Viele Grüße\nTobias Marks")]
        XCTAssertEqual(snippets.match(" Meine Grüsse. "), "Viele Grüße\nTobias Marks")
        XCTAssertEqual(snippets.match("Meine, Grüße!"), "Viele Grüße\nTobias Marks")
        XCTAssertNil(snippets.match("Schick ihr meine Grüße."))
        XCTAssertNil(snippets.match("..."))
        XCTAssertNil([Snippet(phrase: "…", text: "leer")].match("…"))
    }

    func testPipelineInsertsSnippetsUnchangedAndOnlyWhenDictating() {
        let pipeline = TextPipeline(languages: [.german],
                                    replacements: [Replacement(from: "Tobias", to: "Toby")],
                                    snippets: [Snippet(phrase: "Signatur", text: "Gruss, neue Zeile\nTobias")])
        XCTAssertEqual(pipeline.dictation("Signatur."), "Gruss, neue Zeile\nTobias")
        XCTAssertEqual(pipeline.transcript("Signatur."), "Signatur.")
        XCTAssertEqual(pipeline.dictation("Gruss, neue Zeile, Tobias"), "Gruß,\nToby")
        XCTAssertEqual(pipeline.transcript("Gruss, neue Zeile, Tobias"), "Gruß, neue Zeile, Toby")
        var plain = pipeline
        plain.voiceCommands = false
        plain.sharpS = false
        XCTAssertEqual(plain.dictation("Gruss, neue Zeile, Tobias"), "Gruss, neue Zeile, Toby")
    }

    func testTextRulesFileRoundTripAndMerge() throws {
        var replacements = [Replacement(from: "Dum", to: "DAM"), Replacement(from: "Preis", to: "alt")]
        var snippets = [Snippet(phrase: "Signatur", text: "alt")]
        let file = TextRulesFile(replacements: [Replacement(from: "preis", to: "neu")],
                                 snippets: [Snippet(phrase: "signatur!", text: "neu\nzweite Zeile"), Snippet(phrase: "IBAN", text: "DE00")])
        try JSONDecoder().decode(TextRulesFile.self, from: file.data).merge(into: &replacements, &snippets)
        XCTAssertEqual(replacements.map(\.to), ["DAM", "neu"])
        XCTAssertEqual(snippets.map(\.text), ["neu\nzweite Zeile", "DE00"])

        let onlyReplacements = try JSONDecoder().decode(TextRulesFile.self, from: Data(#"{"replacements":[{"from":"a","to":"b"}]}"#.utf8))
        XCTAssertEqual(onlyReplacements.replacements.count, 1)
        XCTAssertTrue(onlyReplacements.snippets.isEmpty)
        XCTAssertThrowsError(try JSONDecoder().decode(TextRulesFile.self, from: Data(#"{"other":1}"#.utf8)))
    }

    func testSnippetPreviewShowsTheFirstLine() {
        XCTAssertEqual(Snippet(phrase: "a", text: "\n Viele Grüße \nTobias").preview, "Viele Grüße …")
        XCTAssertEqual(Snippet(phrase: "a", text: "DE00 1234").preview, "DE00 1234")
    }

    func testTidyRemovesFillersAndRepeatsButNothingElse() {
        let german: Set<SpokenLanguage> = [.german], english: Set<SpokenLanguage> = [.english]
        XCTAssertEqual(TextPolish.tidy("Ähm, also ich wollte sagen, dass ähm das Meeting, äh, bis Freitag, äh, bis Donnerstag geht.", languages: german),
                       "Also ich wollte sagen, dass das Meeting, bis Freitag, bis Donnerstag geht.")
        XCTAssertEqual(TextPolish.tidy("Ich würde, ich würde vorschlagen, dass wir, dass wir warten, weil diese Woche ist, ist voll.", languages: german),
                       "Ich würde vorschlagen, dass wir warten, weil diese Woche ist voll.")
        XCTAssertEqual(TextPolish.tidy("Hallo Tobias,\n\nÄhm, ich wollte fragen, ob du, ob du Zeit hast.\n\nGruß", languages: german),
                       "Hallo Tobias,\n\nIch wollte fragen, ob du Zeit hast.\n\nGruß")
        XCTAssertEqual(TextPolish.tidy("Führ das aus und, ähm, danach den Build. Ähm. Das war's, das war's.", languages: german),
                       "Führ das aus und danach den Build. Das war's.")
        XCTAssertEqual(TextPolish.tidy("I think we should, we should wait until, um, until the numbers are in, uh.", languages: english),
                       "I think we should wait until the numbers are in.")
        // "um" is German, repeated articles are grammar, and clean text is not touched.
        let mixed = "Das sind die, die das wollen, und wir treffen uns um zehn Uhr auf inlaut.de, Version 3.2."
        XCTAssertEqual(TextPolish.tidy(mixed, languages: [.german, .english]), mixed)
        // A spoken line break at either end of a dictation stays (#20).
        XCTAssertEqual(TextPolish.tidy("\n\nÄhm, danke dir ähm\n", languages: german), "\n\nDanke dir\n")
        // Also with the filler between the command and the edge.
        let tidying = TextPipeline(languages: german, tidy: true)
        XCTAssertEqual(tidying.dictation("Das ist der erste Absatz, neuer Absatz, ähm."), "Das ist der erste Absatz.\n\n")
        XCTAssertEqual(tidying.dictation("Hallo, neue Zeile, ähm."), "Hallo,\n")
        XCTAssertEqual(tidying.dictation("Ähm, neuer Absatz, danke dir."), "\n\nDanke dir")
        XCTAssertEqual(tidying.dictation("Ähm, neue Zeile."), "\n")
        XCTAssertEqual(tidying.dictation("Ähm."), "")
        XCTAssertEqual(tidying.dictation("Gut. Ähm neuer Absatz danke dir."), "Gut.\n\nDanke dir")
        XCTAssertEqual(tidying.dictation("Tobias! Ähm neuer Absatz"), "Tobias!\n\n")
        XCTAssertEqual(tidying.dictation("Ich neue Zeile hm neuer Absatz"), "Ich\n\n")
        XCTAssertEqual(tidying.dictation("Wir kommen hm? Äh. Hm? Ähm?"), "Wir kommen?")
    }

    func testCorrectionNeedsACorrectionWordAfterACommaAndSomethingOfTheSameKind() {
        let both: Set<SpokenLanguage> = [.german, .english]
        XCTAssertEqual(TextPolish.correction(in: "Ich brauch die bis Freitag, nein, bis Donnerstag.", languages: both)?.shorter,
                       "Ich brauch die bis Donnerstag.")
        XCTAssertEqual(TextPolish.correction(in: "Der Preis liegt bei zweitausend Euro, nee, dreitausend Euro netto.", languages: both)?.shorter,
                       "Der Preis liegt bei dreitausend Euro netto.")
        XCTAssertEqual(TextPolish.correction(in: "Let's meet at two, I mean at three in the lobby.", languages: both)?.shorter,
                       "Let's meet at three in the lobby.")
        XCTAssertEqual(TextPolish.correction(in: "Die Rechnung für September, nein Oktober, bitte.", languages: both)?.shorter,
                       "Die Rechnung für Oktober, bitte.")
        for sentence in ["Ich sage nein, ich bleibe heute zu Hause.", "Nein, ich habe schon gegessen.",
                         "Ist das fertig, nein, oder?", "Das ist kein Problem, nein, wirklich nicht.",
                         "Der Server ist ausgefallen, also müssen wir den Kunden informieren.",
                         "She said sorry, she was late.", "Das geht nicht, nein."] {
            XCTAssertNil(TextPolish.correction(in: sentence, languages: both), sentence)
        }
        XCTAssertNil(TextPolish.correction(in: "Let's meet at two, I mean at three.", languages: [.german]))
    }

    func testTidyDropsCommasThatOnlyFramedAFiller() {
        let german: Set<SpokenLanguage> = [.german]
        XCTAssertEqual(TextPolish.tidy("Das Meeting ist, äh, um zehn.", languages: german), "Das Meeting ist um zehn.")
        XCTAssertEqual(TextPolish.tidy("Ich hoffe, dass das Update, äh, heute Abend live geht.", languages: german),
                       "Ich hoffe, dass das Update heute Abend live geht.")
        // A restart with a word just said and an aside that goes on keep their comma (#30).
        XCTAssertEqual(TextPolish.tidy("Ich brauch das bis Freitag, äh, bis Donnerstag.", languages: german),
                       "Ich brauch das bis Freitag, bis Donnerstag.")
        XCTAssertEqual(TextPolish.tidy("Das ist, ähm, sagen wir, schwierig.", languages: german), "Das ist, sagen wir, schwierig.")
        XCTAssertEqual(TextPolish.tidy("Ich war bei, äh, Anna.", languages: german), "Ich war bei Anna.")
        XCTAssertEqual(TextPolish.tidy("We meet, uh, at ten.", languages: [.english]), "We meet at ten.")
    }

    func testCorrectionsKnowNumbersMonthsAndWeekdaysWithoutTheTagger() {
        let both: Set<SpokenLanguage> = [.german, .english]
        XCTAssertEqual(TextPolish.correction(in: "Bitte bestell zwanzig, nein, dreißig Stück.", languages: both)?.shorter,
                       "Bitte bestell dreißig Stück.")
        XCTAssertEqual(TextPolish.correction(in: "Please order twenty, no, thirty pieces.", languages: both)?.shorter,
                       "Please order thirty pieces.")
        XCTAssertEqual(TextPolish.correction(in: "Wir liefern am Mittwoch, nein, Donnerstag.", languages: both)?.shorter,
                       "Wir liefern am Donnerstag.")
        XCTAssertNil(TextPolish.correction(in: "Wir liefern am Mittwoch, nein, Oktober.", languages: both))
        for word in ["dreiundzwanzig", "zweitausend", "siebzehn", "sechzig", "dreissig", "twelve", "42"] {
            XCTAssertEqual(TextPolish.WordKind(word), .number, word)
        }
        for word in ["einzig", "sieb", "und", "einen", "achtung", "september"] {
            XCTAssertNotEqual(TextPolish.WordKind(word), .number, word)
        }
    }

    func testTheDotOfADateEndsNoSentence() async {
        let both: Set<SpokenLanguage> = [.german, .english]
        let date = "Der Termin ist am 12. September, nein, am 12. Oktober."
        XCTAssertEqual(TextPolish.sentences(of: date), [date])
        XCTAssertEqual(TextPolish.correction(in: date, languages: both)?.shorter, "Der Termin ist am 12. Oktober.")
        XCTAssertEqual(TextPolish.sentences(of: "Das sind 42. Danach ist Schluss.").count, 2)
        XCTAssertEqual(TextPolish.tidy("Am 3. äh Mai geht es los.", languages: [.german]), "Am 3. Mai geht es los.")
        let resolved = await TextPolish.resolve("Am 12. September, nein, am 13. September. Gut.", languages: both) { _ in true }
        XCTAssertEqual(resolved, "Am 13. September. Gut.")
    }

    func testResolveTakesOnlyConfirmedCorrectionsAndKeepsTheRest() async {
        let both: Set<SpokenLanguage> = [.german, .english]
        let text = "Hallo Frau Becker,\n\nwir liefern am Mittwoch, nein, am Donnerstag. Das kostet vierzig Euro, nee, fünfzig Euro.\n\nViele Grüße"
        var asked: [String] = []
        let all = await TextPolish.resolve(text, languages: both) { asked.append($0.shorter); return true }
        XCTAssertEqual(all, "Hallo Frau Becker,\n\nwir liefern am Donnerstag. Das kostet fünfzig Euro.\n\nViele Grüße")
        XCTAssertEqual(asked, ["wir liefern am Donnerstag. ", "Das kostet fünfzig Euro.\n\n"])
        let none = await TextPolish.resolve(text, languages: both) { _ in false }
        XCTAssertEqual(none, text)
        let first = await TextPolish.resolve(text, languages: both) { $0.spoken.contains("Mittwoch") }
        XCTAssertEqual(first, "Hallo Frau Becker,\n\nwir liefern am Donnerstag. Das kostet vierzig Euro, nee, fünfzig Euro.\n\nViele Grüße")
        XCTAssertEqual(TextPolish.sentences(of: text).joined(), text)
        let leading = await TextPolish.resolve("\nBis Freitag, nein, bis Donnerstag.", languages: both) { _ in true }
        XCTAssertEqual(leading, "\nBis Donnerstag.")
        XCTAssertTrue(TextPolish.mayContainCorrection(text, languages: both))
        XCTAssertFalse(TextPolish.mayContainCorrection("Nein, das geht nicht.", languages: both))
    }

    func testPipelineTidiesOnlyWhenAskedAndNeverInTranscripts() async {
        var pipeline = TextPipeline(languages: [.german])
        let raw = "Ähm, wir liefern am Mittwoch, nein, am Donnerstag."
        XCTAssertEqual(pipeline.dictation(raw), raw)
        pipeline.tidy = true
        XCTAssertEqual(pipeline.dictation(raw), "Wir liefern am Mittwoch, nein, am Donnerstag.")
        XCTAssertEqual(pipeline.transcript(raw), raw)
        let unasked = await pipeline.dictation(raw) { _ in XCTFail("corrections are off"); return true }
        XCTAssertEqual(unasked, "Wir liefern am Mittwoch, nein, am Donnerstag.")
        pipeline.corrections = true
        let resolved = await pipeline.dictation(raw) { _ in true }
        XCTAssertEqual(resolved, "Wir liefern am Donnerstag.")
    }

    func testVoiceCommandsAndUnchangedText() {
        let german: Set<SpokenLanguage> = [.german]
        XCTAssertEqual(VoiceCommands.apply(to: "Hallo Frau Becker, neuer Absatz, vielen Dank für Ihre Nachricht.", languages: german),
                       "Hallo Frau Becker,\n\nVielen Dank für Ihre Nachricht.")
        XCTAssertEqual(VoiceCommands.apply(to: "Das bleibt unverändert.", languages: german), "Das bleibt unverändert.")
        XCTAssertEqual(VoiceCommands.apply(to: "Hallo, neue Zeile, neuer Absatz, Tobias.", languages: german), "Hallo,\n\nTobias")
    }

    func testEnglishVoiceCommandsFollowTheDictationLanguage() {
        // Parakeet Ultra ends sentences with full stops around the commands.
        let ultra = "Hi Sarah, new paragraph, thanks for the quick reply. I will send the file tomorrow. New paragraph. Best regards, new line, Tobias."
        XCTAssertEqual(VoiceCommands.apply(to: ultra, languages: [.english]),
                       "Hi Sarah,\n\nThanks for the quick reply. I will send the file tomorrow.\n\nBest regards,\nTobias")
        // As Ultra wrote the real take: full stops around every command.
        XCTAssertEqual(VoiceCommands.apply(to: "Hi Sarah, new paragraph, thanks for the quick reply. I will send the file tomorrow. New paragraph. Best regards. New line. Tobias.", languages: [.english]),
                       "Hi Sarah,\n\nThanks for the quick reply. I will send the file tomorrow.\n\nBest regards,\nTobias")
        XCTAssertEqual(VoiceCommands.apply(to: "Hallo Frau Becker. Neuer Absatz. Vielen Dank für Ihre Nachricht von gestern. Neuer Absatz. Viele Grüße. Neue Zeile. Tobias.", languages: [.german]),
                       "Hallo Frau Becker,\n\nVielen Dank für Ihre Nachricht von gestern.\n\nViele Grüße,\nTobias")
        // A question or exclamation stays as spoken.
        XCTAssertEqual(VoiceCommands.apply(to: "Alles klar? Neue Zeile. Danke!", languages: [.german]), "Alles klar?\nDanke!")
        // As Parakeet v2 and primeline wrote it.
        let raw = "Hi Sarah, new paragraph, thanks for the quick reply, I will send the file tomorrow, new paragraph, best regards, new line, tobias."
        XCTAssertEqual(VoiceCommands.apply(to: raw, languages: [.english]),
                       "Hi Sarah,\n\nThanks for the quick reply, I will send the file tomorrow.\n\nBest regards,\nTobias")
        XCTAssertEqual(VoiceCommands.apply(to: "First point new line second point", languages: [.english]),
                       "First point\nSecond point")
        // German commands stay text in English mode and vice versa.
        XCTAssertEqual(VoiceCommands.apply(to: raw, languages: [.german]), raw)
        XCTAssertEqual(VoiceCommands.apply(to: "Hallo, neue Zeile, Tobias", languages: [.english]), "Hallo, neue Zeile, Tobias")
        XCTAssertEqual(VoiceCommands.apply(to: "Hallo Sarah, new line, viele Grüße, neue Zeile, Tobias", languages: [.german, .english]),
                       "Hallo Sarah,\nViele Grüße,\nTobias")
    }

    func testSharpSInWordsAndCompounds() {
        XCTAssertEqual(SharpS.apply(to: "Viele Grüsse aus der Hauptstrasse, das ist ausserdem regelmässig ein grosser Spass."),
                       "Viele Grüße aus der Hauptstraße, das ist außerdem regelmäßig ein großer Spaß.")
        XCTAssertEqual(SharpS.apply(to: "Er weiss, was die Massnahme heisst; schliesslich fliesst es draussen."),
                       "Er weiß, was die Maßnahme heißt; schließlich fließt es draußen.")
        XCTAssertEqual(SharpS.apply(to: "Fussball, Weisswein, Eiweiss, Aussendienst, Reissverschluss"),
                       "Fußball, Weißwein, Eiweiß, Außendienst, Reißverschluss")
    }

    func testSharpSLeavesAmbiguousAndCorrectWordsAlone() {
        let unchanged = "Masse Busse floss Schloss muss dass Fluss Strass STRASSE Füssen Fussel Hinweisschild "
            + "Preissenkung Kreissäge aussenden Aussendung Weissagung Ausstellung Eissorte Blossom"
        XCTAssertEqual(SharpS.apply(to: unchanged), unchanged)
    }

    func testCancellationFlag() throws {
        let flag = CancellationFlag()
        try flag.check()
        flag.cancel()
        XCTAssertThrowsError(try flag.check()) { XCTAssertTrue($0 is CancellationError) }
        flag.cancel()
        XCTAssertTrue(flag.isCancelled)
    }

    @MainActor
    func testIndicatorUsesPhysicalEdgeOnOffsetDisplay() {
        let origin = RecordingIndicator.bottomOrigin(size: NSSize(width: 120, height: 32),
                                                     screenFrame: NSRect(x: -1920, y: -200, width: 1920, height: 1080))
        XCTAssertEqual(origin, NSPoint(x: -1020, y: -188))
    }

    func testMeterKeepsPeakAndUpdatesCurrent() throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2))
        buffer.frameLength = 2
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        let meter = Meter()
        samples[0] = -0.8; samples[1] = 0.1
        meter.update(buffer)
        XCTAssertEqual(meter.peak, 0.8)
        samples[0] = 0.2; samples[1] = 0
        meter.update(buffer)
        XCTAssertEqual(meter.current, 0.2)
        XCTAssertEqual(meter.peak, 0.8)
    }

    func testMeterReportsWhenTheFirstSignalArrives() throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2))
        buffer.frameLength = 2
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        let meter = Meter()
        samples[0] = 0; samples[1] = 0
        meter.update(buffer)
        XCTAssertGreaterThanOrEqual(meter.firstBufferMs, 0)
        XCTAssertEqual(meter.firstSignalMs, -1)
        samples[1] = 0.1
        meter.update(buffer)
        XCTAssertGreaterThanOrEqual(meter.firstSignalMs, 0)
    }
}

final class MicrophoneTests: XCTestCase {
    private let builtIn = InputDevice(id: 1, uid: "builtin", name: "MacBook", transport: kAudioDeviceTransportTypeBuiltIn)
    private let headset = InputDevice(id: 2, uid: "headset", name: "Headset", transport: kAudioDeviceTransportTypeBluetooth)
    private let usb = InputDevice(id: 3, uid: "usb", name: "USB", transport: kAudioDeviceTransportTypeUSB)

    func testAutomaticAvoidsBluetoothWhenTheMacHasItsOwnMicrophone() {
        XCTAssertEqual(Microphones.resolve(.automatic, current: headset, among: [headset, builtIn]), builtIn)
    }

    func testAutomaticKeepsBluetoothWithoutABuiltInMicrophone() {
        XCTAssertEqual(Microphones.resolve(.automatic, current: headset, among: [headset, usb]), headset)
    }

    func testAutomaticKeepsAWiredSystemInput() {
        XCTAssertEqual(Microphones.resolve(.automatic, current: usb, among: [headset, builtIn, usb]), usb)
    }

    func testSystemDefaultKeepsBluetooth() {
        XCTAssertEqual(Microphones.resolve(.systemDefault, current: headset, among: [headset, builtIn]), headset)
    }

    func testChosenDeviceWinsAndFallsBackWhenMissing() {
        XCTAssertEqual(Microphones.resolve(.device(uid: "headset"), current: usb, among: [headset, builtIn, usb]), headset)
        XCTAssertEqual(Microphones.resolve(.device(uid: "gone"), current: headset, among: [headset, builtIn]), builtIn)
    }

    func testChoiceSurvivesStorage() {
        for choice in [MicrophoneChoice.automatic, .systemDefault, .device(uid: "usb")] {
            XCTAssertEqual(MicrophoneChoice(stored: choice.stored), choice)
        }
        XCTAssertEqual(MicrophoneChoice(stored: nil), .automatic)
    }
}
