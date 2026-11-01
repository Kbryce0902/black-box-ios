import Foundation
import Combine
import AVFoundation
import BlackBoxCore

@MainActor final class AudioController: ObservableObject {
    @Published var caption = ""
    @Published var listening = false
    @Published var speaking = false
    @Published var status = "Tap the microphone to begin"
    var onFinal: ((String) -> Void)?
    private var playbackEngine = AVAudioEngine()
    private var player = AVAudioPlayerNode()
    private var speech: Task<Void, Never>?
    private var generation = UUID()
    private var observers: [NSObjectProtocol] = []
    private var playbackWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    private let transcription: any TranscriptionProvider
    init(transcription: (any TranscriptionProvider)? = nil) {
        self.transcription = transcription ?? AppleTranscriber()
        self.transcription.onUpdate = { [weak self] text, listening, status in
            self?.caption = text; self?.listening = listening; self?.status = status
        }
        self.transcription.onFinal = { [weak self] text in self?.onFinal?(text) }
        configurePlayback()
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
                        self.transcription.reset(); self.playbackEngine = AVAudioEngine(); self.player = AVAudioPlayerNode(); self.configurePlayback()
                    }
                }
            })
        }
    }
    private func configurePlayback() {
        playbackEngine.attach(player)
        playbackEngine.connect(player, to: playbackEngine.mainMixerNode, format: AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1))
    }
    func begin() async throws { stopSpeech(); try await transcription.begin() }
    func end() { transcription.end() }
    func cancelCapture() { transcription.cancel() }
    func stopSpeech() {
        generation = UUID(); speech?.cancel(); speech = nil; player.stop(); playbackEngine.stop(); speaking = false
        let waits = playbackWaiters.values; playbackWaiters.removeAll(); for wait in waits { wait.resume() }
        status = "Speech stopped"
    }
    func interrupt() {
        cancelCapture(); stopSpeech(); status = "Audio route changed or was interrupted. Tap to resume."
    }
    func speak(_ text: String, client: any SpeechClient) {
        stopSpeech(); let epoch = generation
        speech = Task {
            do {
                let audio = AVAudioSession.sharedInstance()
                try audio.setCategory(.playback, mode: .spokenAudio, options: [.allowBluetoothA2DP])
                try audio.setActive(true); try playbackEngine.start(); player.play(); speaking = true; status = "Requesting ElevenLabs speech…"
                let stream = try await client.audio(text: text)
                var decoder = PCM16Decoder(); var sampleCount = 0
                for try await chunk in stream {
                    try Task.checkCancellation(); guard epoch == generation else { return }
                    let samples = decoder.decode(chunk); if samples.isEmpty { continue }
                    sampleCount += samples.count; status = "Playing ElevenLabs speech"
                    guard let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1),
                          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { throw BBError.wire("Could not allocate audio buffer.") }
                    buffer.frameLength = buffer.frameCapacity
                    samples.withUnsafeBufferPointer { p in buffer.floatChannelData![0].update(from: p.baseAddress!, count: p.count) }
                    // Backpressure bounds queued audio; interruption changes generation before the next buffer.
                    let waiterID = UUID()
                    await withCheckedContinuation { c in
                        playbackWaiters[waiterID] = c
                        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                            Task { @MainActor in self?.playbackWaiters.removeValue(forKey: waiterID)?.resume() }
                        }
                    }
                }
                try decoder.finish()
                guard sampleCount > 0 else { throw BBError.wire("ElevenLabs returned no playable audio. Check the voice/model and test again.") }
                if epoch == generation { speaking = false; status = "Speech complete" }
            } catch {
                if epoch == generation { player.stop(); playbackEngine.stop(); speaking = false; status = error is CancellationError ? "Speech stopped" : error.localizedDescription }
            }
        }
    }
}
