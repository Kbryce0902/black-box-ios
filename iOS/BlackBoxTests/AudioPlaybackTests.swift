import XCTest
import AVFoundation
import BlackBoxCore
@testable import BlackBox

// These tests execute the app's real AVAudioSession/engine/player in iOS.
// Speech bytes are deterministic fixtures; no private key or API call is used.
private func pcmFixture(frames: Int = 9600) -> Data {
    var bytes = Data()
    for frame in 0..<frames {
        let sample = Int16(sin(2 * .pi * 440 * Double(frame) / 24000) * 4000)
        let bits = UInt16(bitPattern: sample)
        bytes.append(UInt8(truncatingIfNeeded: bits)); bytes.append(UInt8(truncatingIfNeeded: bits >> 8))
    }
    return bytes
}
private func fixtureStream(_ bytes: Data, chunkSize: Int = 2048) -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { continuation in
        for offset in stride(from: 0, to: bytes.count, by: chunkSize) {
            continuation.yield(bytes.subdata(in: offset..<min(offset + chunkSize, bytes.count)))
        }
        continuation.finish()
    }
}
private struct FixtureSpeech: SpeechClient {
    var data = pcmFixture()
    var chunkSize = 2048
    func audio(text: String) async throws -> AsyncThrowingStream<Data, Error> { fixtureStream(data, chunkSize: chunkSize) }
}
private struct DeniedSpeech: SpeechClient {
    func audio(text: String) async throws -> AsyncThrowingStream<Data, Error> { throw BBError.setup("Fixture provider denied synthesis") }
}
private actor SuspendedSpeech: SpeechClient {
    var started = false
    private var continuation: CheckedContinuation<AsyncThrowingStream<Data, Error>, Never>?
    func audio(text: String) async throws -> AsyncThrowingStream<Data, Error> {
        started = true
        return await withCheckedContinuation { continuation = $0 }
    }
    func finish() { continuation?.resume(returning: fixtureStream(pcmFixture())); continuation = nil }
}
@MainActor private final class FixtureTranscription: TranscriptionProvider {
    var onUpdate: ((String, Bool, String) -> Void)?
    var onFinal: ((String) -> Void)?
    var cancellations = 0
    func begin() async throws { onUpdate?("Fixture", true, "Fixture listening") }
    func end() { cancel() }
    func cancel() { cancellations += 1; onUpdate?("", false, "Fixture microphone stopped") }
    func reset() { cancel() }
}

@MainActor final class AudioPlaybackTests: XCTestCase {
    private func waitUntil(_ predicate: () -> Bool, timeout: TimeInterval = 8) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate() {
            if Date() > deadline { XCTFail("Timed out waiting for native playback"); throw BBError.setup("Native audio test timed out") }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
    func testPlaybackSessionAndPCMCompleteOnIOS() async throws {
        // Record whether the exact old option combination fails on this runtime.
        // The assertion is successful rendering with the corrected app path;
        // simulator tolerance is not substituted for physical-device evidence.
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.allowBluetoothA2DP])
            print("Legacy playback/Bluetooth probe: accepted by this simulator")
        } catch { print("Legacy playback/Bluetooth probe: \((error as NSError).domain) \((error as NSError).code)") }
        let audio = AudioController(transcription: FixtureTranscription()); defer { audio.stopSpeech() }
        audio.speak("Fixture", client: FixtureSpeech())
        try await waitUntil { !audio.speaking }
        XCTAssertEqual(audio.status, "Speech complete")
        XCTAssertEqual(session.category, .playback); XCTAssertEqual(session.mode, .spokenAudio)
        XCTAssertFalse(audio.outputRoute.isEmpty)
    }
    func testDeviceToneUsesTheRealPlaybackPathWithoutAKey() async throws {
        let audio = AudioController(transcription: FixtureTranscription()); defer { audio.stopSpeech() }
        audio.testDeviceAudio()
        try await waitUntil { !audio.speaking }
        XCTAssertEqual(audio.status, "Device audio test complete. Did you hear the tone?")
    }
    func testRecordingStopsBeforePlaybackAndCanStartAgain() async throws {
        let transcription = FixtureTranscription()
        let captureAudio = AudioController(transcription: transcription); defer { captureAudio.stopSpeech() }
        try await captureAudio.begin(); XCTAssertTrue(captureAudio.listening)
        captureAudio.speak("Fixture", client: FixtureSpeech())
        XCTAssertFalse(captureAudio.listening); XCTAssertGreaterThan(transcription.cancellations, 0)
        try await waitUntil { !captureAudio.speaking }
        XCTAssertEqual(captureAudio.status, "Speech complete")
        try await captureAudio.begin(); XCTAssertTrue(captureAudio.listening); captureAudio.cancelCapture()
    }
    func testStopQueuedPlaybackAndRetryDoNotHang() async throws {
        let audio = AudioController(transcription: FixtureTranscription()); defer { audio.stopSpeech() }
        audio.speak("Long fixture", client: FixtureSpeech(data: pcmFixture(frames: 240000)))
        try await waitUntil { audio.status == "Playing ElevenLabs speech" || !audio.speaking }
        XCTAssertTrue(audio.speaking, audio.status)
        audio.stopSpeech(); XCTAssertEqual(audio.status, "Speech stopped")
        audio.speak("Retry fixture", client: FixtureSpeech())
        try await waitUntil { !audio.speaking }
        XCTAssertEqual(audio.status, "Speech complete")
    }
    func testLateCancelledRequestCannotTouchNewPlayback() async throws {
        let audio = AudioController(transcription: FixtureTranscription()); defer { audio.stopSpeech() }
        let delayed = SuspendedSpeech()
        audio.speak("Old fixture", client: delayed)
        for _ in 0..<300 {
            if await delayed.started { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let started = await delayed.started; XCTAssertTrue(started, audio.status)
        audio.stopSpeech(); audio.testDeviceAudio()
        await delayed.finish()
        try await waitUntil { !audio.speaking }
        XCTAssertEqual(audio.status, "Device audio test complete. Did you hear the tone?")
    }
    func testProviderFailureIsDistinguishedFromNativeSetup() async throws {
        let audio = AudioController(transcription: FixtureTranscription()); defer { audio.stopSpeech() }
        audio.speak("Fixture", client: DeniedSpeech())
        try await waitUntil { !audio.speaking }
        XCTAssertTrue(audio.status.contains("ElevenLabs speech request:"), audio.status)
        XCTAssertTrue(audio.status.contains("Fixture provider denied synthesis"), audio.status)
    }
    func testEmptyAndTruncatedAudioCannotReportSpeechComplete() async throws {
        let audio = AudioController(transcription: FixtureTranscription()); defer { audio.stopSpeech() }
        for data in [Data(), Data([10])] {
            audio.speak("Fixture", client: FixtureSpeech(data: data))
            try await waitUntil { !audio.speaking }
            XCTAssertTrue(audio.status.contains("Speech audio decoding:"), audio.status)
            XCTAssertNotEqual(audio.status, "Speech complete")
        }
    }
    func testInterruptedPlaybackCanRecoverOnNextRequest() async throws {
        let audio = AudioController(transcription: FixtureTranscription()); defer { audio.stopSpeech() }
        audio.speak("Long fixture", client: FixtureSpeech(data: pcmFixture(frames: 240000)))
        try await waitUntil { audio.status == "Playing ElevenLabs speech" || !audio.speaking }
        audio.interrupt(); XCTAssertFalse(audio.speaking)
        audio.testDeviceAudio()
        try await waitUntil { !audio.speaking }
        XCTAssertEqual(audio.status, "Device audio test complete. Did you hear the tone?")
    }
    func testOddPCMChunksAndNewlineSampleBytesPlayToCompletion() async throws {
        let audio = AudioController(transcription: FixtureTranscription()); defer { audio.stopSpeech() }
        // Includes 0x0a on both byte positions and boundaries inside PCM samples.
        let bytes = Data(repeating: 10, count: 4800)
        audio.speak("Fixture", client: FixtureSpeech(data: bytes, chunkSize: 511))
        try await waitUntil { !audio.speaking }
        XCTAssertEqual(audio.status, "Speech complete")
    }
}
