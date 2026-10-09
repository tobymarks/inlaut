import CryptoKit
import Foundation

struct ModelFile: Hashable, Sendable {
    let name: String
    let size: Int64
    let sha256: String
}

/// One Parakeet model as compiled Core ML components (Preprocessor, Encoder,
/// Decoder, JointDecisionv3) for FluidAudio, run on the Neural Engine. Each
/// is pinned to one revision with known checksums, so every install runs
/// exactly the bits that were tested.
struct SpeechModel: Identifiable, Hashable, Sendable {
    /// Also the directory name under Models/.
    let id: String
    let name: String
    /// Languages it recognises well enough to offer (measured, not claimed).
    let languages: Set<String>
    let repo: String
    let revision: String
    let files: [ModelFile]
    /// Markdown credit line for Settings.
    let credit: String

    /// moondream's post-training of NVIDIA Parakeet TDT 0.6B v3 (CC BY 4.0),
    /// Core ML export by FluidInference. On the maintainer's own German,
    /// English and mixed takes and on FLEURS it beat primeline (German) and
    /// v2 (English), writes ß and full stops, and runs on the Neural Engine
    /// with ~20× less CPU and ~550 MB less memory than the ONNX models.
    static let ultra = SpeechModel(
        id: "parakeet-ultra-coreml",
        name: String(localized: "Parakeet Ultra"),
        languages: ["de", "en"],
        repo: "FluidInference/parakeet-ultra-coreml",
        revision: "95eaa59a39d4394f047a4dc5cce480388a60d1b6",
        files: [
            ModelFile(name: "Decoder.mlmodelc/analytics/coremldata.bin", size: 243,
                      sha256: "fe92b6cfaa012abd5248c0bc877832f19807015abffc60d87b8ccc8ccb48b3b5"),
            ModelFile(name: "Decoder.mlmodelc/weights/weight.bin", size: 23_604_992,
                      sha256: "02a0d219f281b9665bc10c8768649403b2eebbbf4b44c627041d948e0de11bb4"),
            ModelFile(name: "Decoder.mlmodelc/coremldata.bin", size: 560,
                      sha256: "3b06e66768f0df7e21795f50e2b29300e33eeb1a2579dc42c695279c2d308497"),
            ModelFile(name: "Decoder.mlmodelc/model.mil", size: 13_110,
                      sha256: "956f600207f88396017ca5c96cfa3acd5bfee60835a5b44b762e033a8fb28955"),
            ModelFile(name: "Encoder.mlmodelc/analytics/coremldata.bin", size: 243,
                      sha256: "d87101d824d6723cf95304da33755c3c60e762663b9ef2b0c4bd0aa166a09a0d"),
            ModelFile(name: "Encoder.mlmodelc/weights/weight.bin", size: 594_211_328,
                      sha256: "315ba01f33cadbf601d43ac7f5c86208b7aa75fdaa34705c9869d5abe3521c9b"),
            ModelFile(name: "Encoder.mlmodelc/coremldata.bin", size: 514,
                      sha256: "397a84a4062f563cbc5f56077c674f09a61d85be5090f61d2f1932afb92ac0fe"),
            ModelFile(name: "Encoder.mlmodelc/model.mil", size: 1_002_653,
                      sha256: "f5d601568a4171d99a314c0fe3f6bc67715da2623732a3fb566e050ea83e5848"),
            ModelFile(name: "JointDecisionv3.mlmodelc/analytics/coremldata.bin", size: 243,
                      sha256: "68d38ca646aebafa7a9329e2efda50f5767c49e89fdb5f77f212072bb66f97c4"),
            ModelFile(name: "JointDecisionv3.mlmodelc/weights/weight.bin", size: 12_642_764,
                      sha256: "3f310b85b82341c53ec383025ab094a4e462ee1c592e1ad7c6bfe39cff66ca25"),
            ModelFile(name: "JointDecisionv3.mlmodelc/coremldata.bin", size: 592,
                      sha256: "5e3af5a4ce686f6c237cadbd9284e10d333bc0e1546633cd0e430e6194044bc4"),
            ModelFile(name: "JointDecisionv3.mlmodelc/model.mil", size: 11_777,
                      sha256: "791b3c3cf3eb2079c84623fc880f6bba008d1366e5f8b03e9a8ed8bd4d7194a0"),
            ModelFile(name: "Preprocessor.mlmodelc/analytics/coremldata.bin", size: 243,
                      sha256: "c9beeb989c8d66f8be11df59bc6df277ec76cee404f6865b46243835ef562f6d"),
            ModelFile(name: "Preprocessor.mlmodelc/weights/weight.bin", size: 491_072,
                      sha256: "129b76e3aeafa8afa3ea76d995b964b145fe83700d579f6ff42c4c38fa0968ea"),
            ModelFile(name: "Preprocessor.mlmodelc/coremldata.bin", size: 486,
                      sha256: "dbde3f2300842c1fd51ef3ff948a0bcffe65ffd2dca10707f2509f32c1d65b1d"),
            ModelFile(name: "Preprocessor.mlmodelc/metadata.json", size: 2_841,
                      sha256: "2a98699e22d279dd37fa1d238aeb1c6db1df0d6fad687775324157689d8f3acf"),
            ModelFile(name: "Preprocessor.mlmodelc/model.mil", size: 28_181,
                      sha256: "4b8518a956450fec57f06c2a21bdffc26973f7f1fa6842fb38fe917f896b6b93"),
            ModelFile(name: "parakeet_vocab.json", size: 151_122,
                      sha256: "7ec60e05f1b24480736ec0eed40900f4626bce1fa9a60fd700ec7e2a59198735"),
        ],
        credit: String(localized: "[Parakeet Ultra](https://huggingface.co/moondream/parakeet-ultra) (moondream) based on [NVIDIA Parakeet TDT 0.6B v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3), both CC BY 4.0, Core ML export by [FluidInference](https://huggingface.co/FluidInference/parakeet-ultra-coreml)"))

    static let catalogue = [ultra]

    static func with(id: String) -> SpeechModel? { catalogue.first { $0.id == id } }

    var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }

    var directory: URL { directory(in: ModelStore.root) }

    func directory(in root: URL) -> URL { root.appending(path: id, directoryHint: .isDirectory) }

    func url(_ name: String) -> URL { directory.appending(path: name) }

    /// Files only reach their final name after the checksum passed, so a
    /// matching size is enough here.
    func isComplete(_ file: ModelFile) -> Bool {
        let size = (try? FileManager.default.attributesOfItem(atPath: url(file.name).path)[.size] as? Int64) ?? nil
        return size == file.size
    }

    var isInstalled: Bool { files.allSatisfy(isComplete) }

    /// Downloads what is missing. `progress` gets 0…1 on the main actor.
    @MainActor
    func install(progress: @escaping @MainActor (Double) -> Void) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var done = files.filter(isComplete).reduce(Int64(0)) { $0 + $1.size }
        progress(Double(done) / Double(totalBytes))

        for file in files where !isComplete(file) {
            try Task.checkCancellation()
            let source = URL(string: "https://huggingface.co/\(repo)/resolve/\(revision)/\(file.name)")!
            let base = done
            let total = totalBytes
            let temp = try await Download.run(source) { written in
                progress(Double(base + written) / Double(total))
            }
            defer { try? FileManager.default.removeItem(at: temp) }
            let hashing = Task.detached(priority: .userInitiated) { try ModelStore.sha256(of: temp) }
            let hash = try await withTaskCancellationHandler {
                try await hashing.value
            } onCancel: {
                hashing.cancel()
            }
            try Task.checkCancellation()
            guard hash == file.sha256 else {
                throw EngineError("Checksum of \(file.name) does not match – the download is damaged.")
            }
            let target = url(file.name)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: temp, to: target)
            done += file.size
            progress(Double(done) / Double(totalBytes))
        }
    }

    func delete() {
        try? FileManager.default.removeItem(at: directory)
    }
}

enum ModelStore {
    static var root: URL {
        URL.applicationSupportDirectory.appending(path: "Inlaut/Models", directoryHint: .isDirectory)
    }

    /// Only one model stays on disk (~650 MB each). Removes every other
    /// catalogue model, including one left half-downloaded by an interrupted
    /// switch; unknown directories are left alone.
    static func removeAll(except kept: SpeechModel, in root: URL = root) {
        for model in SpeechModel.catalogue where model != kept {
            try? FileManager.default.removeItem(at: model.directory(in: root))
        }
        removeLegacy(in: root)
    }

    /// The sherpa-onnx models of 0.1–0.2 (primeline, v2). Nothing can run them
    /// any more since the switch to Core ML.
    static let legacyIDs = ["parakeet-primeline-int8", "parakeet-tdt-0.6b-v2-int8"]

    static func hasLegacy(in root: URL = root) -> Bool {
        legacyIDs.contains { FileManager.default.fileExists(atPath: root.appending(path: $0).path) }
    }

    static func removeLegacy(in root: URL = root) {
        for id in legacyIDs { try? FileManager.default.removeItem(at: root.appending(path: id)) }
    }

    nonisolated static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        // Each read returns autoreleased data; without a pool per chunk a
        // 600 MB model stays in memory until the thread's pool drains.
        while try autoreleasepool(invoking: {
            guard let chunk = try handle.read(upToCount: 8 << 20), !chunk.isEmpty else { return false }
            hasher.update(data: chunk)
            return true
        }) {
            try Task.checkCancellation()
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// One file download with byte progress, via a delegate session.
private final class Download: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<URL, Error>?
    private let onProgress: @Sendable (Int64) -> Void
    private var lastReported: Int64 = 0

    private init(onProgress: @escaping @Sendable (Int64) -> Void) {
        self.onProgress = onProgress
    }

    @MainActor
    static func run(_ url: URL, progress: @escaping @MainActor (Int64) -> Void) async throws -> URL {
        try Task.checkCancellation()
        let download = Download { written in Task { @MainActor in progress(written) } }
        let session = URLSession(configuration: .default, delegate: download, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                download.continuation = continuation
                session.downloadTask(with: url).resume()
            }
        } onCancel: {
            session.invalidateAndCancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        // About every 4 MB is plenty for a progress bar.
        if totalBytesWritten - lastReported > 4 << 20 {
            lastReported = totalBytesWritten
            onProgress(totalBytesWritten)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The system deletes `location` when this method returns.
        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
            finish(.failure(EngineError("Download failed (HTTP \(http.statusCode)).")))
            return
        }
        let kept = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        do {
            try FileManager.default.moveItem(at: location, to: kept)
            finish(.success(kept))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }

    private func finish(_ result: Result<URL, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}
