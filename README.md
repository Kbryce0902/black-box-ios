# Black_Box — native iOS assistant

Black_Box is implemented as one native SwiftUI app and a reusable Swift core. It calls Gemini, ElevenLabs and the existing RDC hosted MCP service directly. There is no custom backend, local language model or consumer-app dependency.

**Status: compiled 0.1.2 development IPA for SideStore.** Xcode 26.3 built the arm64
iphoneos Release target using the iOS 26.2 SDK; 64 Mac core tests passed.
`BlackBox-0.1.2-unsigned.ipa` was retrieved and its checksum/structure verified.
SideStore must sign it for the phone. The owner reports 0.1.0 installed and runs;
0.1.2 real-device acceptance, provider calls and
RDC desktop integration remain unverified. See [HANDOFF.md](HANDOFF.md) and
[Verification/RESULTS.md](Verification/RESULTS.md).

## Start here

1. Read [docs/FEASIBILITY.md](docs/FEASIBILITY.md): RDC's live dynamic registration returned a confidential client despite requesting a public native client. The app rejects that result. An RDC-issued public native client registration is the smallest supported next step. Do not embed a client secret or reuse another app's token.
2. On a suitable Mac, open `BlackBox.xcodeproj`. The app uses the local package in `Package.swift` and Apple system frameworks only. Select the BlackBox scheme and your iPhone.
3. Run `Scripts/test-core.sh` and `Scripts/build-ios.sh simulator`. For SideStore, after a successful device build run `Scripts/build-ios.sh unsigned`. This creates an unsigned IPA only when a real Apple SDK build succeeds.
4. Follow [docs/SETUP.md](docs/SETUP.md), enter your keys in the app's secure Settings fields, then run the native feasibility harness. Keys never belong in source, chat or build logs.
5. Finish the real-device checklist in [docs/ACCEPTANCE.md](docs/ACCEPTANCE.md). A simulated tool loop is not proof of phone-to-PC control.

The [GitHub Actions build](docs/CLOUD_BUILD.md) runs in the dedicated public
[black-box-ios repository](https://github.com/Kbryce0902/black-box-ios).
The verified build is [run 41297291686](https://github.com/Kbryce0902/black-box-ios/actions/runs/41297291686).

## Included implementation

- 0.1.2 fixes ElevenLabs setup and speech: documented model IDs/display-name
  normalization, returned TTS model picker, bounded metadata checks, redacted
  provider error reasons and an explicit Test voice control. Voice/model edits
  autosave. Restricted TTS-only keys can test speech independently of read access.

- 0.1.1 fixes Gemini setup: Save and check key starts automatically, with progress,
  cancellation, a 25-second deadline, inline Google errors and a returned-model
  picker. Settings checks an already saved key. Keys and history retain their
  existing storage identity; metadata success does not claim inference success.

- Conversation, Computer, Activity and Settings tabs; native dark styling, blue accents and a featureless cube app icon.
- SQLite history, task/action journaling, editable memories and device-specific folder aliases; Keychain credentials on iOS.
- Gemini streaming REST client, opaque thought-signature preservation, correlated function responses, bounded loop and separate Google Search grounding requests.
- Tappable sources, preserved grounding support markers and Google's rendered attribution in an isolated, JavaScript-disabled web view.
- Independent RDC discovery, public-client PKCE flow, refresh/revocation adapters, MCP initialization/session handling, schema checks and explicit device binding. Provider interoperability remains gated by Module 00.
- Foreground push-to-talk with final-transcript-only dispatch, captions and streamed ElevenLabs PCM; stop/replay/mute and independent task cancellation.
- Structured, allowlisted desktop helpers and Windows acceptance script; file operations require explicit review and never overwrite. No generated shell-code tool, advanced browser automation or privileged installation capability is exposed.
- Recovery marks interrupted operations unknown or blocked. Reconnection does not replay them. Remote call retrieval is available when RDC supplies an ID and advertises the tool.

## Source map

| Path | Purpose |
|---|---|
| `iOS/BlackBox` | Native UI, Keychain, OAuth browser session, microphone and audio playback |
| `Sources/BlackBoxCore` | Provider clients, policy, durable journal, tool execution and wire parsing |
| `Tests/BlackBoxCoreTests` | Deterministic protocol and execution tests; all doubles labeled Fixture |
| `Desktop` | Windows PowerShell helper and opt-in desktop acceptance script |
| `Scripts` | Local core tests, real Apple builds and public metadata probe |
| `Verification` | Actual check outputs and redacted live registration evidence |

No API keys, OAuth tokens, provisioning identities or client secrets are included. The public repository was created with owner authorization; no paid service was enabled.
