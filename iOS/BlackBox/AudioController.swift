import Foundation
import Combine
import AVFoundation
import BlackBoxCore

@MainActor final class AudioController: ObservableObject {
    @Published var caption = ""
    @Published var listening = false
    @Published var speaking = false
    @Published var status = "Tap the microphone to begin"
    @Published var outputRoute = ""
    var onFinal: ((String) -> Void)?
    private var playbackEngine = AVAudioEngine()
    private var player = AVAudioPlayerNode()
    private var speech: Task<Void, Never>?
    private var generation = UUID()
    private var observers: [NSObjectProtocol] = []
    private var playbackWaiters: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var queuedBuffers: Set<UUID> = []
    private let transcription: any TranscriptionProvider
    init(transcription: (any TranscriptionProvider)? = nil) {
        self.transcription = transcription ?? AppleTranscriber()
        self.transcription.onUpdate = { [weak self] text, listening, status in
            self?.caption = text; self?.listening = listening; self?.status = status
        }
        self.transcription.onFinal = { [weak self] text in self?.onFinal?(text) }
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification, AVAudioSession.mediaServicesWereResetNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                // Our own .playback/.playAndRecord changes must not interrupt a new stream.
                if name == AVAudioSession.routeChangeNotification {
                    guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                          let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
                    guard [.oldDeviceUnavailable, .newDeviceAvailable, .noSuitableRouteForCategory, .override].contains(reason) else { return }
                }
                let reset = name == AVAudioSession.mediaServicesWereResetNotification
                Task { @MainActor in
                    guard let self else { return }; self.interrupt()
                    if reset {
                        self.transcription.reset(); self.playbackEngine = AVAudioEngine(); self.player = AVAudioPlayerNode()
                    }
                }
            })
        }
    }
    private func preparePlayback() throws {
        // Build against the active output route, rather than keeping a graph made
        // before activation or before a microphone/Bluetooth category change.
        playbackEngine = AVAudioEngine(); player = AVAudioPlayerNode()
        playbackEngine.attach(player)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1) else { throw BBError.setup("Could not create the speech audio format.") }
        playbackEngine.connect(player, to: playbackEngine.mainMixerNode, format: format)
        playbackEngine.prepare(); try playbackEngine.start(); player.play()
    }
    func begin() async throws { stopSpeech(); try await transcription.begin() }
    func end() { transcription.end() }
    func cancelCapture() { transcription.cancel() }
    func stopSpeech() {
        generation = UUID(); speech?.cancel(); speech = nil; player.stop(); playbackEngine.stop(); speaking = false
        queuedBuffers.removeAll()
        let waits = Array(playbackWaiters.values); playbackWaiters.removeAll(); for wait in waits { wait.resume(throwing: CancellationError()) }
        status = "Speech stopped"
    }
    func interrupt() {
        cancelCapture(); stopSpeech(); status = "Audio route changed or was interrupted. Tap to resume."
    }
    private func checkCurrent(_ epoch: UUID) throws {
        try Task.checkCancellation()
        guard epoch == generation else { throw CancellationError() }
    }
    private func waitForPlayback(below limit: Int, epoch: UUID) async throws {
        try checkCurrent(epoch)
        while queuedBuffers.count >= limit {
            let id = UUID()
            let deadline = Task { @MainActor [weak self] in
                do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
                self?.playbackWaiters.removeValue(forKey: id)?.resume(throwing: BBError.setup("iPhone audio playback stalled. Check the output route and try Test device audio."))
            }
            defer { deadline.cancel() }
            try await withCheckedThrowingContinuation { playbackWaiters[id] = $0 }
            try checkCurrent(epoch)
        }
    }
    private func bufferPlayed(_ id: UUID, epoch: UUID) {
        guard epoch == generation, queuedBuffers.remove(id) != nil else { return }
        let waits = Array(playbackWaiters.values); playbackWaiters.removeAll()
        for wait in waits { wait.resume() }
    }
    func testDeviceAudio() { speak("", client: DeviceAudioSample(), source: "Device audio") }
    func speak(_ text: String, client: any SpeechClient, source: String = "ElevenLabs speech") {
        stopSpeech(); cancelCapture(); let epoch = generation
        speaking = true; status = "Preparing iPhone audio…"
        speech = Task {
            var stage = "iPhone audio session setup"
            defer {
                if epoch == generation { player.stop(); playbackEngine.stop(); speaking = false; speech = nil }
            }
            do {
                try checkCurrent(epoch)
                let audio = AVAudioSession.sharedInstance()
                // Playback already supports A2DP. Explicit Bluetooth options are
                // for recording categories and can produce kAudio_ParamError (-50).
                try audio.setCategory(.playback, mode: .spokenAudio, options: [])
                stage = "iPhone audio activation"; try audio.setActive(true)
                outputRoute = audio.currentRoute.outputs.map(\.portName).joined(separator: ", ")
                stage = "iPhone playback engine"; try preparePlayback()
                stage = source + " request"; status = "Requesting \(source)…"
                let stream = try await client.audio(text: text)
                try checkCurrent(epoch)
                var decoder = PCM16Decoder(); var sampleCount = 0
                for try await chunk in stream {
                    try checkCurrent(epoch)
                    let samples = decoder.decode(chunk); if samples.isEmpty { continue }
                    sampleCount += samples.count; status = "Playing \(source)"
                    stage = "iPhone audio playback"
                    for start in stride(from: 0, to: samples.count, by: 1024) {
                        // Keep a bounded runway queued instead of waiting for each
                        // tiny network chunk to finish before scheduling the next.
                        try await waitForPlayback(below: 8, epoch: epoch)
                        let count = min(1024, samples.count - start)
                        guard let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1),
                              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
                              let channel = buffer.floatChannelData?[0] else { throw BBError.wire("Could not allocate audio buffer.") }
                        buffer.frameLength = buffer.frameCapacity
                        samples.withUnsafeBufferPointer { p in channel.update(from: p.baseAddress! + start, count: count) }
                        let id = UUID(); queuedBuffers.insert(id)
                        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                            Task { @MainActor in self?.bufferPlayed(id, epoch: epoch) }
                        }
                    }
                    stage = source + " stream"
                }
                stage = "Speech audio decoding"
                try decoder.finish()
                guard sampleCount > 0 else { throw BBError.wire("ElevenLabs returned no playable audio. Check the voice/model and test again.") }
                stage = "iPhone audio playback"; try await waitForPlayback(below: 1, epoch: epoch)
                status = source == "Device audio" ? "Device audio test complete. Did you hear the tone?" : "Speech complete"
            } catch {
                if epoch == generation {
                    let ns = error as NSError
                    status = error is CancellationError ? "Speech stopped" : "\(stage): \(error.localizedDescription) [\(ns.domain) \(ns.code)]"
                }
            }
        }
    }
}

/// A local PCM fixture exercises the identical session, decoder and player path
/// without a provider key, network request, speech fallback or quota consumption.
private struct DeviceAudioSample: SpeechClient {
    func audio(text: String) async throws -> AsyncThrowingStream<Data, Error> {
        var data = Data()
        for frame in 0..<14400 {
            let fade = min(1, Double(min(frame, 14399 - frame)) / 480)
            let sample = Int16(sin(2 * .pi * 440 * Double(frame) / 24000) * 5000 * fade)
            let bits = UInt16(bitPattern: sample)
            data.append(UInt8(truncatingIfNeeded: bits)); data.append(UInt8(truncatingIfNeeded: bits >> 8))
        }
        return AsyncThrowingStream { continuation in
            for start in stride(from: 0, to: data.count, by: 2048) { continuation.yield(data.subdata(in: start..<min(start + 2048, data.count))) }
            continuation.finish()
        }
    }
}
