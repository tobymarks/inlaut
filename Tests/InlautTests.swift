import AppKit
import AVFoundation
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

    func testVoiceCommandsAndUnchangedText() {
        let german: Set<SpokenLanguage> = [.german]
        XCTAssertEqual(VoiceCommands.apply(to: "Hallo Frau Becker, neuer Absatz, vielen Dank für Ihre Nachricht.", languages: german),
                       "Hallo Frau Becker,\n\nVielen Dank für Ihre Nachricht.")
        XCTAssertEqual(VoiceCommands.apply(to: "Das bleibt unverändert.", languages: german), "Das bleibt unverändert.")
        XCTAssertEqual(VoiceCommands.apply(to: "Hallo, neue Zeile, neuer Absatz, Tobias.", languages: german), "Hallo,\n\nTobias")
    }

    func testEnglishVoiceCommandsFollowTheDictationLanguage() {
        // As Parakeet v2 and primeline write it.
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
}
