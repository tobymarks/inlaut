// Spike: Apple's on-device SpeechAnalyzer/SpeechTranscriber (macOS 26+) on a WAV file.
//   swiftc -O spike/try_apple.swift -o spike/try_apple && spike/try_apple spike/test.wav
import AVFoundation
import Foundation
import Speech

func rssMB() -> Double {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    _ = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return Double(info.resident_size) / 1e6
}

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let locale = Locale(identifier: "de-DE")

let supported = await SpeechTranscriber.supportedLocales
print("de-DE supported:", supported.contains { $0.identifier(.bcp47) == "de-DE" })

let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [])
if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
    print("downloading speech assets...")
    try await request.downloadAndInstall()
}

let t0 = Date()
let analyzer = SpeechAnalyzer(modules: [transcriber])
// Optional custom vocabulary, comma-separated: TERMS="DAM,AWS" spike/try_apple file.wav
if let terms = ProcessInfo.processInfo.environment["TERMS"], !terms.isEmpty {
    let context = AnalysisContext()
    context.contextualStrings[.general] = terms.split(separator: ",").map { String($0) }
    try await analyzer.setContext(context)
}
let file = try AVAudioFile(forReading: url)
let collector = Task {
    var text = ""
    for try await result in transcriber.results { text += String(result.text.characters) }
    return text
}
if let last = try await analyzer.analyzeSequence(from: file) {
    try await analyzer.finalizeAndFinish(through: last)
} else {
    await analyzer.cancelAndFinishNow()
}
let text = try await collector.value
print(String(format: "[decoded in %.0f ms, RSS %.0f MB]", Date().timeIntervalSince(t0) * 1000, rssMB()))
print(text)
