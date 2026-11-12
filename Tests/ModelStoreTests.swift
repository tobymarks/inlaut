import XCTest

final class ModelStoreTests: XCTestCase {
    func testCatalogueIsConsistent() {
        let catalogue = SpeechModel.catalogue
        XCTAssertEqual(Set(catalogue.map(\.id)).count, catalogue.count)
        for model in catalogue {
            XCTAssertEqual(model.revision.count, 40, model.id)
            XCTAssertEqual(Set(model.files.map(\.name)).count, model.files.count, model.id)
            // What FluidAudio's AsrModels.loadLocal(version: .ultra) opens.
            for component in ["Preprocessor", "Encoder", "Decoder", "JointDecisionv3"] {
                for part in ["coremldata.bin", "model.mil", "weights/weight.bin"] {
                    XCTAssertTrue(model.files.contains { $0.name == "\(component).mlmodelc/\(part)" },
                                  "\(model.id) lacks \(component).mlmodelc/\(part)")
                }
            }
            XCTAssertTrue(model.files.contains { $0.name == "parakeet_vocab.json" }, model.id)
            for file in model.files {
                XCTAssertEqual(file.sha256.count, 64, file.name)
                XCTAssertTrue(file.sha256.allSatisfy(\.isHexDigit), file.name)
                XCTAssertGreaterThan(file.size, 0, file.name)
                XCTAssertFalse(file.name.hasPrefix("/") || file.name.contains(".."), file.name)
            }
            XCTAssertEqual(SpeechModel.with(id: model.id), model)
        }
        XCTAssertNil(SpeechModel.with(id: "parakeet-primeline-int8"))
    }

    func testRemovesOtherAndLegacyModelsButKeepsUnknownDirectories() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let unknown = root.appending(path: "something-else")
        let legacy = ModelStore.legacyIDs.map { root.appending(path: $0) }
        let kept = SpeechModel.catalogue[0]
        for directory in [kept.directory(in: root), unknown] + legacy {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: directory.appending(path: "tokens.txt"))
        }
        XCTAssertTrue(ModelStore.hasLegacy(in: root))

        ModelStore.removeAll(except: kept, in: root)

        let exists = { (url: URL) in FileManager.default.fileExists(atPath: url.path) }
        XCTAssertTrue(exists(kept.directory(in: root)))
        XCTAssertTrue(exists(unknown))
        XCTAssertFalse(legacy.contains(where: exists))
        XCTAssertFalse(ModelStore.hasLegacy(in: root))
    }

    func testSHA256() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("abc".utf8).write(to: file)
        XCTAssertEqual(try ModelStore.sha256(of: file),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    /// Fetches 23 MB from Hugging Face, so it only runs when asked to:
    /// `TEST_RUNNER_INLAUT_NETWORK_TESTS=1 xcodebuild … test`.
    @MainActor
    func testInterruptedDownloadContinues() async throws {
        guard ProcessInfo.processInfo.environment["INLAUT_NETWORK_TESTS"] == "1" else {
            throw XCTSkip("needs the network")
        }
        let model = SpeechModel.ultra
        let file = try XCTUnwrap(model.files.first { $0.name == "Decoder.mlmodelc/weights/weight.bin" })
        let source = try XCTUnwrap(URL(string: "https://huggingface.co/\(model.repo)/resolve/\(model.revision)/\(file.name)"))
        let downloaded = try await Download.run(source, interruptAfter: 6 << 20) { _ in }
        defer { try? FileManager.default.removeItem(at: downloaded) }
        XCTAssertEqual(try ModelStore.sha256(of: downloaded), file.sha256)
    }
}
