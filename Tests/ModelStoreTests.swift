import XCTest

final class ModelStoreTests: XCTestCase {
    func testCatalogueIsConsistent() {
        let catalogue = SpeechModel.catalogue
        XCTAssertEqual(Set(catalogue.map(\.id)).count, catalogue.count)
        // Existing installs live in this directory; renaming it would re-download.
        XCTAssertEqual(SpeechModel.primeline.id, "parakeet-primeline-int8")
        for model in catalogue {
            XCTAssertEqual(model.revision.count, 40, model.id)
            XCTAssertEqual(Set(model.files.map(\.name)).count, model.files.count, model.id)
            for name in ["encoder.int8.onnx", "decoder.int8.onnx", "joiner.int8.onnx", "tokens.txt"] {
                XCTAssertTrue(model.files.contains { $0.name == name }, "\(model.id) lacks \(name)")
            }
            for file in model.files {
                XCTAssertEqual(file.sha256.count, 64, file.name)
                XCTAssertTrue(file.sha256.allSatisfy(\.isHexDigit), file.name)
                XCTAssertGreaterThan(file.size, 0, file.name)
            }
            XCTAssertEqual(SpeechModel.with(id: model.id), model)
        }
        XCTAssertNil(SpeechModel.with(id: "unknown"))
    }

    func testRemovesOtherModelsButKeepsUnknownDirectories() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let unknown = root.appending(path: "something-else")
        for directory in SpeechModel.catalogue.map({ $0.directory(in: root) }) + [unknown] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: directory.appending(path: "tokens.txt"))
        }

        ModelStore.removeAll(except: .parakeetV2, in: root)

        let exists = { (url: URL) in FileManager.default.fileExists(atPath: url.path) }
        XCTAssertTrue(exists(SpeechModel.parakeetV2.directory(in: root)))
        XCTAssertFalse(exists(SpeechModel.primeline.directory(in: root)))
        XCTAssertTrue(exists(unknown))
    }

    func testSHA256() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("abc".utf8).write(to: file)
        XCTAssertEqual(try ModelStore.sha256(of: file),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
