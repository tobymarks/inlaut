// Usage: spike/eval_apple <locale>  ; reads WAV paths from stdin, prints one JSON line per file.
import AVFoundation
import Foundation
import Speech

let locale = Locale(identifier: CommandLine.arguments[1])
guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else { fatalError("unsupported") }
let probe = SpeechTranscriber(locale: supported, transcriptionOptions: [], reportingOptions: [], attributeOptions: [])
if let request = try await AssetInventory.assetInstallationRequest(supporting: [probe]) {
    FileHandle.standardError.write("downloading assets\n".data(using: .utf8)!)
    try await request.downloadAndInstall()
}
while let line = readLine() {
    let transcriber = SpeechTranscriber(locale: supported, transcriptionOptions: [], reportingOptions: [], attributeOptions: [])
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    let t0 = Date()
    let file = try AVAudioFile(forReading: URL(fileURLWithPath: line))
    let collector = Task { var t = ""; for try await r in transcriber.results { t += String(r.text.characters) }; return t }
    if let last = try await analyzer.analyzeSequence(from: file) { try await analyzer.finalizeAndFinish(through: last) }
    else { await analyzer.cancelAndFinishNow() }
    let text = try await collector.value
    let obj: [String: Any] = ["path": line, "text": text, "secs": Date().timeIntervalSince(t0)]
    print(String(data: try JSONSerialization.data(withJSONObject: obj), encoding: .utf8)!)
}
