import Foundation
import AVFoundation
import Speech
import BlackBoxCore

@MainActor protocol TranscriptionProvider: AnyObject {
    var onUpdate: ((String, Bool, String) -> Void)? { get set }
    var onFinal: ((String) -> Void)? { get set }
    func begin() async throws
    func end()
    func cancel()
    func reset()
}

@MainActor final class AppleTranscriber: TranscriptionProvider {
    var onUpdate: ((String, Bool, String) -> Void)?
    var onFinal: ((String) -> Void)?
    private var engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?
    private var tapInstalled = false
    private var committed = false
    private var generation = UUID()
    private var caption = ""
    private var finalization: Task<Void, Never>?
    func begin() async throws {
        cancel(); generation = UUID(); let epoch = generation; committed = false; caption = ""
        let mic = await withCheckedContinuation { c in AVAudioSession.sharedInstance().requestRecordPermission { c.resume(returning: $0) } }
        let permission = await withCheckedContinuation { c in SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) } }
        guard epoch == generation else { throw CancellationError() }
        guard mic, permission == .authorized else { throw BBError.setup("Enable microphone and speech recognition in iPhone Settings.") }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.isAvailable else { throw BBError.setup("Apple speech recognition is unavailable on this device or network.") }
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
        try audio.setActive(true)
        let req = SFSpeechAudioBufferRecognitionRequest(); req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req
        let input = engine.inputNode; let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw BBError.setup("No usable microphone input route.") }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in req.append(buffer) }; tapInstalled = true
        recognition = recognizer.recognitionTask(with: req) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString; let final = result?.isFinal ?? false
            Task { @MainActor in
                guard let self, epoch == self.generation else { return }
                if let text { self.caption = text; self.onUpdate?(text, !final, "Listening · partial captions never run commands") }
                if final, !self.committed, let text, !text.isEmpty {
                    self.committed = true; self.finalization?.cancel(); self.finishCapture()
                    self.onUpdate?(text, false, "Final transcript committed"); self.onFinal?(text)
                } else if error != nil { self.cancel(); self.onUpdate?(self.caption, false, "Transcription stopped. Review captions or type a request.") }
            }
        }
        do { engine.prepare(); try engine.start() } catch { cancel(); throw error }
        onUpdate?(caption, true, recognizer.supportsOnDeviceRecognition ? "Listening · on-device Apple recognition" : "Listening · Apple network recognition")
    }
    func end() {
        finishCapture(); onUpdate?(caption, false, "Finalizing transcript…")
        let epoch = generation
        finalization = Task {
            do { try await Task.sleep(nanoseconds: 10_000_000_000) } catch { return }
            if generation == epoch, !committed { cancel(); onUpdate?(caption, false, "No final transcript received. Review captions and submit typed text.") }
        }
    }
    private func finishCapture() {
        engine.stop(); if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }; request?.endAudio()
    }
    func cancel() {
        generation = UUID(); committed = true; finalization?.cancel(); finalization = nil
        finishCapture(); recognition?.cancel(); recognition = nil; request = nil
        onUpdate?(caption, false, "Microphone stopped")
    }
    func reset() { cancel(); engine = AVAudioEngine() }
}
