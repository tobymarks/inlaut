import CryptoKit
import Foundation

struct ModelFile: Hashable, Sendable {
    let name: String
    let size: Int64
    let sha256: String
}

/// One Parakeet model (int8 ONNX for sherpa-onnx). Each is pinned to one
/// revision with known checksums, so every install runs exactly the bits
/// that were tested. Only one of them is kept on disk at a time.
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

    /// German Parakeet (primeline fine-tune of nvidia/parakeet-tdt-0.6b-v3),
    /// CC-BY-4.0. Also nearly as good as v2 on English and best on mixed
    /// German/English sentences.
    static let primeline = SpeechModel(
        id: "parakeet-primeline-int8",
        name: "Parakeet Deutsch",
        languages: ["de", "en"],
        repo: "flozen1981/parakeet-primeline-onnx",
        revision: "d548e25b9bfe559aa274f361892dc4ed5d64743a",
        files: [
            ModelFile(name: "encoder.int8.onnx", size: 1_548_009,
                      sha256: "d4232f86718da0330167fb10789d1a35cffe6a60cd58239957943a8d9bc24c63"),
            ModelFile(name: "encoder.int8.onnx.data", size: 650_776_320,
                      sha256: "d3b0d27912043d38a3c2ce4f2c03124be30bc1ff57d976302908954b2e8fe7bb"),
            ModelFile(name: "decoder.int8.onnx", size: 11_845_275,
                      sha256: "fb4ddefe200706cabb27ee3fc1c81efa50555a4c8a8e00b663cc795216fb9369"),
            ModelFile(name: "joiner.int8.onnx", size: 6_355_277,
                      sha256: "8220c0d117d81bdd0d8c770881932ac340f1ce4b36932941d561d11ad1aaffce"),
            ModelFile(name: "tokens.txt", size: 102_132,
                      sha256: "ba8e4007c65f4bb4358ffe2ecc13d9ccc7a10351151065242b5c3a943e685742"),
        ],
        credit: "[parakeet-primeline](https://huggingface.co/primeline/parakeet-primeline) (primeline) auf Basis von [NVIDIA Parakeet TDT 0.6B v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3), beide CC BY 4.0")

    /// NVIDIA's English-only Parakeet, the lowest English error rate measured.
    static let parakeetV2 = SpeechModel(
        id: "parakeet-tdt-0.6b-v2-int8",
        name: "Parakeet English",
        languages: ["en"],
        repo: "csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8",
        revision: "1ab9323565ddb038682214b292f588070a538ce2",
        files: [
            ModelFile(name: "encoder.int8.onnx", size: 652_184_296,
                      sha256: "a32b12d17bbbc309d0686fbbcc2987b5e9b8333a7da83fa6b089f0a2acd651ab"),
            ModelFile(name: "decoder.int8.onnx", size: 7_257_753,
                      sha256: "b6bb64963457237b900e496ee9994b59294526439fbcc1fecf705b31a15c6b4e"),
            ModelFile(name: "joiner.int8.onnx", size: 1_739_080,
                      sha256: "7946164367946e7f9f29a122407c3252b680dbae9a51343eb2488d057c3c43d2"),
            ModelFile(name: "tokens.txt", size: 9_384,
                      sha256: "ec182b70dd42113aff6c5372c75cac58c952443eb22322f57bbd7f53977d497d"),
        ],
        credit: "[NVIDIA Parakeet TDT 0.6B v2](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2), CC BY 4.0")

    static let catalogue = [primeline, parakeetV2]

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
                throw EngineError("Prüfsumme von \(file.name) stimmt nicht – Download beschädigt.")
            }
            let target = url(file.name)
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
    }

    nonisolated static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 8 << 20), !chunk.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: chunk)
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
            finish(.failure(EngineError("Download fehlgeschlagen (HTTP \(http.statusCode)).")))
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
