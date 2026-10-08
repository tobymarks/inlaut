import CryptoKit
import Foundation

struct ModelFile: Sendable {
    let name: String
    let size: Int64
    let sha256: String
}

/// German Parakeet (primeline fine-tune of nvidia/parakeet-tdt-0.6b-v3),
/// int8 ONNX, CC-BY-4.0. Pinned to one revision with known checksums, so
/// every install runs exactly the bits that were tested.
enum ParakeetModel {
    static let repo = "flozen1981/parakeet-primeline-onnx"
    static let revision = "d548e25b9bfe559aa274f361892dc4ed5d64743a"
    static let files = [
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
    ]

    static var totalBytes: Int64 { files.reduce(0) { $0 + $1.size } }

    static var directory: URL {
        URL.applicationSupportDirectory.appending(path: "Inlaut/Models/parakeet-primeline-int8", directoryHint: .isDirectory)
    }

    static func url(_ name: String) -> URL { directory.appending(path: name) }

    /// Files only reach their final name after the checksum passed, so a
    /// matching size is enough here.
    static func isComplete(_ file: ModelFile) -> Bool {
        let size = (try? FileManager.default.attributesOfItem(atPath: url(file.name).path)[.size] as? Int64) ?? nil
        return size == file.size
    }

    static var isInstalled: Bool { files.allSatisfy(isComplete) }

    /// Downloads what is missing. `progress` gets 0…1 on the main actor.
    @MainActor
    static func install(progress: @escaping @MainActor (Double) -> Void) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var done = files.filter(isComplete).reduce(Int64(0)) { $0 + $1.size }
        progress(Double(done) / Double(totalBytes))

        for file in files where !isComplete(file) {
            let source = URL(string: "https://huggingface.co/\(repo)/resolve/\(revision)/\(file.name)")!
            let base = done
            let temp = try await Download.run(source) { written in
                progress(Double(base + written) / Double(totalBytes))
            }
            defer { try? FileManager.default.removeItem(at: temp) }
            let hash = try await Task.detached(priority: .userInitiated) { try sha256(of: temp) }.value
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

    nonisolated private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 8 << 20), !chunk.isEmpty {
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
