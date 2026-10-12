import AppKit
import os
import SwiftUI
import UniformTypeIdentifiers

/// The transcript of one recording. It lives in memory only; nothing is
/// written to disk unless the user saves it.
@MainActor
@Observable
final class FileTranscript {
    enum Phase: Equatable {
        case empty
        case running(Double)
        case done
        case failed(String)
    }

    private(set) var phase: Phase = .empty
    private(set) var fileName = ""
    private(set) var parts: [TranscriptPart] = []
    private var task: Task<Void, Never>?
    private var run: UUID?
    private let log = Logger(subsystem: "de.tobymarks.inlaut", category: "file")

    var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    func text(timestamps: Bool) -> String {
        parts.map { timestamps ? "[\($0.clock)] \($0.text)" : $0.text }.joined(separator: "\n\n")
    }

    func start(_ url: URL, state: AppState) {
        cancel()
        let id = UUID()
        run = id
        fileName = url.lastPathComponent
        parts = []
        // One engine for the whole file, so every piece gets the same format.
        guard let engine = state.recordingEngine else {
            phase = .failed(String(localized: "Speech recognition is not ready yet."))
            return
        }
        phase = .running(0)
        state.isTranscribingFile = true
        let started = Date()
        task = Task { [weak self, weak state] in
            defer { if self?.run == id { state?.isTranscribingFile = false } }
            do {
                try await FileTranscription.run(url) {
                    try engine.begin()
                } report: { part, fraction in
                    guard let self, self.run == id else { return }
                    if let part, let text = state?.textPipeline.transcript(part.text), !text.isEmpty {
                        self.parts.append(TranscriptPart(start: part.start, text: text))
                    }
                    self.phase = .running(fraction)
                }
                guard let self, self.run == id else { return }
                // Length and timing only — the text is never logged.
                let seconds = Date().timeIntervalSince(started)
                self.log.notice("file: \(self.parts.reduce(0) { $0 + $1.text.count }) chars in \(seconds, format: .fixed(precision: 1))s")
                self.phase = self.parts.isEmpty ? .failed(String(localized: "Nothing recognized")) : .done
            } catch {
                guard let self, self.run == id, !(error is CancellationError) else { return }
                self.log.error("file failed: \(error.localizedDescription)")
                self.phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Keeps what has been transcribed so far.
    func cancel() {
        guard isRunning else { return }
        task?.cancel()
        task = nil
        run = nil
        phase = parts.isEmpty ? .empty : .done
    }
}

/// Opened by AppState, like the setup window.
@MainActor
final class TranscriptWindow {
    let transcript = FileTranscript()
    private var window: NSWindow?

    func show(state: AppState) {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(
                rootView: TranscriptView(state: state, transcript: transcript)))
            window.title = String(localized: "Transcribe a Recording")
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 620, height: 520))
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct TranscriptView: View {
    let state: AppState
    let transcript: FileTranscript
    @AppStorage("transcriptTimestamps") private var timestamps = false
    @State private var dropTargeted = false

    static let fileTypes: [UTType] = [.audio, .movie] + [UTType(filenameExtension: "webm")].compactMap { $0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(transcript.fileName.isEmpty ? String(localized: "Turn a recording into text") : transcript.fileName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.inlautInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Audio or video. The file is turned into text on this Mac and never leaves it.")
                    .font(.callout)
                    .foregroundStyle(Color.inlautMuted)
            }

            if transcript.phase == .empty {
                dropZone
            } else {
                TextEditor(text: .constant(transcript.text(timestamps: timestamps)))
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color.inlautSurface, in: .rect(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.inlautBorder))
            }

            footer
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 400)
        .background(Color.inlautPaper)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            transcript.start(url, state: state)
            return true
        } isTargeted: { dropTargeted = $0 }
    }

    private var dropZone: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 34))
                .foregroundStyle(Color.inlautAccent)
            Text("Drop a file here")
                .font(.headline)
                .foregroundStyle(Color.inlautInk)
            Button("Choose File …") { state.chooseFileToTranscribe() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.inlautSurface, in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .stroke(dropTargeted ? Color.inlautAccent : Color.inlautBorder,
                    style: StrokeStyle(lineWidth: dropTargeted ? 2 : 1, dash: [6, 4])))
    }

    @ViewBuilder
    private var footer: some View {
        switch transcript.phase {
        case .empty:
            EmptyView()
        case .running(let fraction):
            HStack(spacing: 12) {
                ProgressView(value: fraction)
                Text("\(Int(fraction * 100)) %")
                    .monospacedDigit()
                    .foregroundStyle(Color.inlautMuted)
                Button("Cancel") { transcript.cancel() }
            }
        case .failed(let message):
            HStack {
                Text(message).foregroundStyle(Color.inlautRecording)
                Spacer()
                Button("Choose File …") { state.chooseFileToTranscribe() }
            }
        case .done:
            HStack {
                Toggle("Time stamps", isOn: $timestamps)
                Spacer()
                Button("Choose File …") { state.chooseFileToTranscribe() }
                Button("Save …") { save() }
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(transcript.text(timestamps: timestamps), forType: .string)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func save() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = (transcript.fileName as NSString).deletingPathExtension + ".txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try transcript.text(timestamps: timestamps).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

#if DEBUG
/// End-to-end tests: `-transcribeFile /in.wav -transcribeOutput /out.txt`
/// transcribes a recording once the engine is ready, writes the text with
/// time stamps and quits. `-renderTranscript /path.png` adds a picture of
/// the window, or shows the empty one when it is the only argument.
@MainActor
enum TranscriptProbe {
    static func runIfRequested(state: AppState) {
        let defaults = UserDefaults.standard
        let input = defaults.string(forKey: "transcribeFile")
        let picture = defaults.string(forKey: "renderTranscript")
        guard input != nil || picture != nil else { return }
        Task {
            let transcript = FileTranscript()
            if let input {
                for _ in 0..<240 where state.recordingEngine == nil { try? await Task.sleep(for: .milliseconds(500)) }
                let started = Date()
                transcript.start(URL(fileURLWithPath: input), state: state)
                while transcript.isRunning { try? await Task.sleep(for: .milliseconds(100)) }
                let text = "phase: \(transcript.phase), \(String(format: "%.2f", Date().timeIntervalSince(started))) s\n\n"
                    + transcript.text(timestamps: true)
                if let output = defaults.string(forKey: "transcribeOutput") {
                    try? text.write(toFile: output, atomically: true, encoding: .utf8)
                }
            }
            if let picture {
                let host = NSHostingView(rootView: TranscriptView(state: state, transcript: transcript))
                host.frame = NSRect(x: 0, y: 0, width: 620, height: 520)
                let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
                window.contentView = host
                window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
                window.orderFront(nil)
                try? await Task.sleep(for: .seconds(1))
                host.layoutSubtreeIfNeeded()
                if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                    host.cacheDisplay(in: host.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: picture))
                }
            }
            NSApp.terminate(nil)
        }
    }
}
#endif
