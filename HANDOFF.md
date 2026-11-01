# Black_Box implementation handoff

Updated 2026-11-01. Source version **0.1.3 development**. Continue this repository;
do not restart from a proposal.

## Native speech playback repair — 0.1.3

The owner installed 0.1.2. ElevenLabs metadata succeeds for the selected voice
and eleven_v4, but Test voice displays OSStatus -50 with no speech. The screenshot
contains no live API key. Its private Voice ID was not copied into source/tests.
The old controller reported a generic error across multiple native setup stages,
so the screenshot alone cannot identify which native call failed.

Changes implemented and compiled:
- Playback uses playback/spokenAudio without an explicit Bluetooth flag;
  playback already routes to A2DP. The engine graph is recreated after session
  activation instead of keeping a graph built before the active route existed.
- Microphone capture stops before output. Requesting, playback and failure
  stages distinguish session setup, activation, engine, provider request/stream,
  decoding and render failures, including the native error domain/code.
- ElevenLabs PCM is binary. The HTTP reader no longer treats 0x0a sample bytes
  as SSE newlines. It emits 2048-byte packets plus a final tail.
- An eight-buffer runway replaces serial single-buffer draining, with at most
  1024 frames per buffer. Samples remain 24 kHz mono Float32 decoded from the
  provider's PCM16; the mixer converts to the hardware route.
- Stop/interruption releases waits and invalidates old callbacks/requests. Each
  new request gets a new graph. A stalled render wait has a five-second deadline.
- Settings has Test device audio (no API usage) through the same decoder/player,
  and shows the actual output route. Test voice remains an explicit quota-using
  action. No alternate voice provider or automatic retry was introduced.
- 0.1.3/build 4 preserves bundle ID, Keychain, SQLite and configured providers.

Verification: all **64 portable core tests** and **nine native iOS audio tests**
passed in run 41317287989. Xcode 26.3 built the Release arm64 device IPA and ran
the hosted app/player tests on the arm64 iOS 26.2 simulator. The native tests
cover real session/engine/buffer completion, a local tone, capture ownership via
a fixture transcriber, stop/retry, stale requests, provider-vs-native errors,
empty/truncated/odd PCM and interruption recovery. No real microphone or API key
was used by these tests. Local plist/YAML/XML/Bash checks pass.

The legacy playback/Bluetooth combination was accepted by this simulator. It did
**not reproduce the owner's exact physical-device -50**. The repaired native
path executes successfully here; actual phone playback and Bluetooth routes
still need owner acceptance. Do not turn simulator success into a live account
or device success. Literal run excerpts are in Verification/audio-0.1.3.log.

Official Apple references checked 2026-11-01:
https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions-swift.struct/allowbluetootha2dp
https://developer.apple.com/documentation/avfaudio/avaudiosession/mode-swift.struct/spokenaudio

## ElevenLabs setup/speech fix — 0.1.2

The owner reports HTTP 400 while checking ElevenLabs after supplying a key and
Voice ID. The screenshot also shows the display label ElevenV4 in the model
field. The app's voice-only GET did not send a model, so the screenshot alone
cannot establish the cause of that GET's 400. The old HTTP layer discarded all
ElevenLabs error bodies. No live private key was available to reproduce it here.

Confirmed and corrected app defects:
- A typed model label was passed unchanged to speech. Official Eleven v4 API
  ID is eleven_v4. Known display names now normalize to documented IDs in the
  client and existing saved preferences; unknown/future exact IDs are retained.
- Keys and Voice IDs trim copy/paste whitespace; Voice ID case is preserved.
- Voice/model metadata checks use the documented v1/models and v1/voices/{id}
  endpoints, validate response types/identity, and populate a TTS-only model
  picker. Metadata success never implies synthesis or quota success.
- HTTP and speech-stream errors now preserve bounded/redacted ElevenLabs
  status/message with a stage label. Missing endpoint permissions, invalid
  voice/model, quotas and verification errors are distinguished. JSON errors
  are never decoded as PCM. A custom Accept header was removed;
  the documented pcm_24000 query controls raw audio output.
- A cancellable 25-second metadata deadline and revision IDs reject stale
  replies after key/voice changes. Normalization feedback does not cancel a
  newly started check. All model/voice edits save automatically.
- Test voice (uses API quota), Stop test speech and actual audio result now
  appear beside setup. A TTS-only key can test speech despite missing read
  permissions; metadata never becomes a hidden prerequisite for synthesis.
- Playback distinguishes requesting from receiving audio and rejects an empty
  stream. It never auto-retries a potentially billed synthesis call.
- Release 0.1.2, build 3; app, Keychain and SQLite identities are unchanged.

All **64 Mac core tests passed**, including 16 new ElevenLabs regressions for
request construction, normalization, read-vs-speech permissions, metadata
correlation, provider errors/redaction, retry, deadlines and stale responses.
Native arm64 Release compilation, packaging and downloaded artifact integrity
checks PASS in run 41297291686. Local plist/YAML/shell checks PASS; the expired
Linux Swift toolchain was not reinstalled or reported as a new Linux test pass.
Live private-key/voice acceptance still requires the owner's phone test.

Official references checked 2026-11-01:
https://elevenlabs.io/docs/api-reference/voices/get
https://elevenlabs.io/docs/api-reference/models/list
https://elevenlabs.io/docs/api-reference/text-to-speech/stream
https://elevenlabs.io/docs/help-center/product/core-capabilities/text-to-speech/how-do-audio-tags-work-with-eleven-v3-and-v4

## Gemini setup fix — 0.1.1

Owner reports that 0.1.0 installed through SideStore and launches on the phone.
The Settings screenshot shows a stored key with the static validation-pending
label. This does not identify an actual Google authentication error.

Confirmed code defects: saving the key did not start validation; failed checks
only set a separate alert and never replaced the pending status; there was no
in-progress state, bounded UI deadline or displayed returned-model selection.
Gemini and ElevenLabs also shared one status label. Google's current official
documentation confirms gemini-3.8-flash is a valid ID; no default-model swap or
claim about this key's access was justified.

Implemented in the same app:
- Saving a Gemini key automatically starts a metadata-only check. Settings also
  checks an already stored key when opened. Keys remain in the same Keychain
  service; SQLite location and bundle identifier are unchanged.
- Progress, cancellation, success, missing-model and failure states are inline.
  A 25-second independent deadline clears progress even if transport cancellation
  is ignored. Revision IDs reject responses after replacement, deletion or timeout.
- Model discovery follows bounded pagination, filters generateContent support,
  normalizes models/ prefixes and populates a native picker with returned IDs.
  Selection is saved. Model listing does not prove inference/quota access.
- Gemini HTTP errors retain bounded, sanitized Google status/reason/message;
  known echoed keys are removed. No raw response body/header/key is logged.
- ElevenLabs uses its own status. Native speech and RDC gates are unchanged.
- Release 0.1.1, build 2. Packaging derives the artifact version from Info.plist.

Checks: portable core build PASS; **48 tests passed, 0 failures** on Linux.
The 14 new regressions cover catalogs/pagination, bad keys/permissions/quota,
offline status, deadline, retry, replacement/deletion races, model changes and
key redaction. Native syntax and shell/YAML/version checks PASS. Native Mac compilation and packaging of 0.1.1 PASS in run 41291008404; all 48
tests passed on that Mac too. No user API key or live Google success was available
here; do not substitute fixture results for that proof.

Official references checked 2026-11-01:
https://ai.google.dev/api/models
https://ai.google.dev/gemini-api/docs/models/gemini-3.8-flash
https://ai.google.dev/gemini-api/docs/api-key

Current release provenance is recorded below.

## Current outcome

**Native 0.1.3 (build 4) has been compiled, tested, retrieved and preserved.**

- Repository: https://github.com/Kbryce0902/black-box-ios (owner-authorized public
  repository containing only this project).
- Exact compiled source: `3ff7ce92f24c1ec685a772a62e6647603e669988`.
- Successful run: https://github.com/Kbryce0902/black-box-ios/actions/runs/41317287989
  (job 124879916457; all workflow steps succeeded).
- macOS 15.8.2 arm64, Xcode 26.3 (17C529), Apple Swift 6.2.4; iOS 26.2 SDK.
  Release arm64 iphoneos, minimum iOS 17.0; simulator tests also use iOS 26.2.
- **64 Mac core tests + nine native iOS audio tests passed; zero failures.**
- `BlackBox-0.1.3-unsigned.ipa`: 867221 bytes, bundle com.kellen.blackbox.
- IPA SHA-256: `94a5b23a09137f78db339f08e2f1a7a5974b37f0d20c5a117b074c64a3449630`.
- GitHub artifact 13088301355; outer ZIP SHA-256: `5de00dda8a737ab78243807bce9fd99285e72ff46dd3c1534fe3aa0394f0f155`.
- Downloaded ZIP and enclosed IPA matched both digests. ZIP integrity, version,
  executable permissions, arm64 Mach-O and physical iOS platform checks passed
  independently after download.

Install over the existing app through SideStore. The owner reports 0.1.2 install,
launch and live voice/model metadata success, followed by native playback -50.
This 0.1.3 update and actual private-key speech have not been phone-verified.
Saved keys, bundle ID and SQLite location remain unchanged. Voice/model edits
have autosaved since 0.1.2; no need to re-enter a working key to test this repair.

No real provider key, private Voice ID, signing identity or voice material was
uploaded to the repository. No paid provider request, subscription or account
permission change occurred here. Metadata success is not synthesis proof.
Test device audio is local; Test voice is the explicit live provider test.

**RDC's native public-client registration gate remains unresolved.**

## Compilation changes and checkpoints

1. Created the dedicated public repository after explicit owner authorization.
2. Run 41288013816 passed 34 tests but could not find the Xcode project because
   the upload manifest omitted that existing directory. Commit
   `a6e1523ddd710c9f794367e081e2f9fdfd4b284e` added the project and shared scheme.
3. Run 41288221772 compiled the native app successfully but packaging failed
   because lipo -verify_arch was passed the input in the wrong position.
4. Commit `dbec5b93dd1d20e209462f5c7076871c1970cb34` corrected the argument order.
   Run 41288398459 passed compilation, packaging, verification and upload.
5. 0.1.1 commit `9cec8dcfbad11e0d402f0e566f91a9e9c5d440d3` fixes Gemini setup;
   run 41291008404 passed 48 tests, native compilation, packaging and artifact checks.
6. 0.1.2 commit `93af30d7d00bf4abc4c6eb959ca92ec64494b636` fixes ElevenLabs
   setup and model IDs. Run 41297291686 passed 64 tests, native compilation and
   verified packaging. Documentation-only updates do not alter that binary.

7. 0.1.3 initial commit `bf0c389232e5d370ada5c4acec582b462fb09fc1` passed 64
   core tests and native packaging in run 41316725723, but the simulator build
   attempted an x86_64 app against arm64 SwiftPM. No audio tests ran in that attempt.
8. Commit `3ff7ce92f24c1ec685a772a62e6647603e669988` selects the host simulator architecture and
   ONLY_ACTIVE_ARCH. Run 41317287989 passed all 64 core and nine native audio tests,
   device compilation, packaging and artifact verification. Subsequent docs-only
   updates do not alter those compiled source bytes.

The prepared workflow skips private-repository Mac jobs before allocation and
retains artifacts for one day. No private runner minutes or paid-service/billing
settings were enabled. The standalone IPA was saved for delivery because GitHub
artifacts expire. Source is now maintained in this repository.

Known non-fatal compiler warnings: older Apple microphone/Bluetooth spellings,
a weak-self capture warning under future Swift 6 language mode, and skipped
AppIntents metadata because the app does not use AppIntents. Compilation used
Swift 5 language mode as configured. No warning was promoted to a device test.

## Module checkpoints

| Module | Implemented and integrated | Verification / remaining gate |
|---|---|---|
| 00 Feasibility | Native Settings harness for Gemini response, ElevenLabs playback, RDC discovery/public PKCE and device enumeration | Live metadata/DCR checked. DCR returned confidential client; native consent, token exchange, refresh, revocation, devices and cellular pending |
| 01 Foundation | Four SwiftUI tabs, Keychain, SQLite, typed task/action contracts, native project/icon | Core storage/policy tests pass. Apple Keychain/UI require Xcode/device. No production mock path; Fixture doubles live only in Tests |
| 02 Gemini | REST/SSE conversation, complete continuation parts, bounded serial tool loop, error/result correlation | Parser/execution tests pass. User key/model inference pending |
| 03 Desktop | Explicit selection, live schema/device checks, aliases, file search/read, fixed URL/app/path helpers, actual-resource helper | Policy/encoding/evidence-parser tests pass. Real service output shapes and Windows operations remain unverified |
| 04 Voice | Replaceable TranscriptionProvider, Apple finalized captions, streamed ElevenLabs PCM, stop/replay/mute, independent cancellation, routing/interruption handlers | 64 core and nine native iOS audio tests pass. Physical permissions, speaker/headset and private-key synthesis pending |
| 05 Research/memory | Separate Google-grounded research tool, sources/support markers/rendered attribution, editable memories, per-device aliases | Citation/UTF-8 tests pass; actual grounding and UI attribution acceptance pending |
| 06 Recovery | Transactional claims, no duplicate dispatch/replay, persisted unknown outcomes, saved-call reconciliation on resume, public-client refresh/revocation adapter and reported usage limits | Recovery/cancellation/duplicate/refresh fixtures pass. Native suspension/token/server-revocation tests pending |
| 07 Release | Xcode configuration, actual-build-only unsigned packaging script, SideStore/PC startup instructions and acceptance checklist | Mac arm64 Release build, 64 core + nine iOS audio tests, verified 0.1.3 unsigned IPA PASS; SideStore signing/install and real-device acceptance pending |

All modules use the same app, contracts and persistence. The first vertical slice passes only with deterministic fixtures: text → model tool → validation → persisted action → fixture RDC executor → correlated model response. Real YouTube launch is still pending Module 00. Voice is integrated behind that same execution boundary, not evidence that the live slice passed.

## Exact RDC finding

- Official MCP transport: https://mcp.desktopcommander.app/mcp.
- Live protected-resource identifier: https://mcp.desktopcommander.app (origin).
- Authorization metadata advertises S256, authorization_code, refresh_token, `none` and `client_secret_post`; no revocation endpoint was advertised.
- One registration requested application_type=native, token auth `none`, callback `com.kellen.blackbox:/oauth/callback`, authorization_code + refresh_token.
- Response accepted the callback but returned `client_secret_post` and a nonempty secret. Only redacted metadata is in Verification/. The temporary raw registration response was deleted. No secret/client ID was embedded in source and no user grant/token was obtained.
- App rejects this result. Settings accepts a **provider-issued public native client ID** as the smallest supported configuration change to test. Do not add a secret to the app, borrow ChatGPT tokens or introduce a custom backend as a hidden workaround.
- Unknown service response formats fail closed. Capture real, redacted native device/tool/search/helper responses after authentication and refine the versioned adapters as needed.

## Initial Linux checks and provider versions

- Inspected workspace was empty; no existing source or AGENTS.md found. No unrelated files changed.
- Host: Ubuntu 24.04 x86_64; no Swift initially, no Xcode, Apple SDKs, signing identity or connected iPhone.
- Portable checks: downloaded Swift 6.0.3; OS SQLite 3.45.1 runtime / extracted development headers; Swift-tools manifest 5.9, Swift 5 language mode.
- `swift build --build-tests --jobs 1 -Xswiftc -disable-batch-mode` with local include/link paths: PASS.
- Direct XCTest executable: **34 tests, 0 failures**. See Verification/core-direct-tests.log.
- Default launcher intermittently hits a host /proc monitoring crash; see Verification/attempts and RESULTS.md. Serial build + a separate direct test invocation passed.
- `swift-frontend -parse iOS/BlackBox/*.swift`: PASS, syntax only.
- OpenStep project parser, all native source references, Info.plist and scheme XML: PASS.
- PowerShell 7.4.6 parser on Linux: PASS for both .ps1 files. Windows 10 / PowerShell 5.1 execution: NOT RUN.
- Bash build/test script syntax and Python probe compilation: PASS.
- `Scripts/build-ios.sh simulator` on Linux: expected BLOCKED exit 2, no fake IPA.
- Current default Gemini ID: gemini-3.8-flash, configurable and supported in checked official documentation; account availability not verified.
- Current default ElevenLabs TTS model: eleven_flash_v2_5, voice ID unset; PCM16 mono 24 kHz stream.
- iOS deployment floor: 17. Apple documentation checked for Xcode 27.x/current OS support; actual iPhone hardware/OS must be verified by native harness. No marketing-name mapping is assumed.

## Material decisions to preserve

- Direct provider connections; no consumer-app dependency, custom backend or local model.
- Separate grounded request avoids assuming mixed custom/built-in tool compatibility.
- Persist all complete Gemini content parts and function IDs; do not reconstruct thought signatures.
- Device selection is explicit and pinned. No first-device auto-selection or stale offline replay.
- Desktop commands require complete transcripts/complete model responses and a live helper gate. Only fixed structured helpers exist; arbitrary shell/browser clicking is absent.
- Claim actions before dispatch. Unknown outcomes stop further dispatch; existing-call retrieval is read-only and never restarts the task automatically.
- Helper launch acknowledgement is not an observed page/window. Media acknowledgement is not inspected playback. A started process without a complete helper result is unknown.
- Credential-like files are excluded, excerpts bounded/redacted, tool/document output treated as data. Provider keys remain outside model context and SQLite.
- Apple recognition is replaceable. Audio ignores its own category-change notifications, invalidates stale generations, releases playback waits on stop and rebuilds after media-services reset. These native behaviors still require device testing.
- Stop speech and task cancellation remain separate. Backgrounding cancels foreground dispatch/audio; there is no keepalive/wakeword promise.
- Replay currently synthesizes the saved answer again through ElevenLabs and can consume quota; no cached audio replay is implemented.
- New folder/file moves require a concrete review and never overwrite. Financial/destructive/communication/installation/privileged tools are not exposed.

## Missing inputs / environment

1. User's Gemini API key and available model (enter in native Settings; never paste into handoff/source/logs).
2. ElevenLabs key and accessible Voice ID are stored on the owner's phone and 0.1.2 metadata success is reported. They are unavailable in this build environment; 0.1.3 live synthesis acceptance remains pending. No target voice was created here.
3. RDC-confirmed public native registration with token auth none, S256, exact callback, mcp:tools scope, advertised resource audience, refresh and supported grant-revocation route.
4. Actual selected Windows PC/agent online after this app's own OAuth consent; helper path and per-device folder aliases; actual Windows, PowerShell, Node and RDC versions.
5. User-side SideStore update to 0.1.3 and real speech/output-route acceptance. Native device compilation and simulator audio execution are complete.

## Next concrete step

Install 0.1.3 through SideStore over the current app. In Settings, use Test device
audio (no API usage) and check the Output route, then Test voice (uses API quota).
The existing selected voice/model/key are retained. Record whether the local
tone and provider speech are audible on speaker/headset. If a failure remains,
record its exact stage and sanitized inline reason, never the key. Update
acceptance with the actual physical-device result. Continue RDC public-native
registration separately before claiming phone-to-PC control.
