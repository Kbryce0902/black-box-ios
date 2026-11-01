# Black_Box implementation handoff

Updated 2026-11-01. Source version **0.1.3 development**. Continue this repository;
do not restart from a proposal.

## Native speech playback fix — 0.1.3 (verification in progress)

The owner installed 0.1.2. ElevenLabs metadata now succeeds for the chosen voice
and eleven_v4, but Test voice displays OSStatus -50 and no audio. The screenshot
contains no live API key. Do not copy its private Voice ID into source/tests.

The old controller set playback + spokenAudio + allowBluetoothA2DP before its
first synthesis request. Playback already supports A2DP; remove the explicit
recording-category option. Rebuild the engine graph only after session activation
so stale microphone/Bluetooth formats are not retained. Cancel microphone capture
before output. Local setup/activation/engine, provider request/stream, decoding
and render failures now have distinct stage labels and native error codes.

The generic HTTP reader also flushed raw PCM on every 0x0a byte. Audio is binary,
so ElevenLabs now emits full 2048-byte packets (plus a final tail). A bounded
8-buffer playback runway replaces one-buffer-at-a-time waiting; buffers remain
24 kHz mono Float32 decoded from provider PCM16, and the mixer converts to the
active output route. Stop/interruption releases waiters, rejects stale callbacks
and permits a new graph on retry; stalled rendering has a 5-second deadline.

Settings adds Test device audio (no API usage), using a local tone through the
same PCM/session/player path, plus the actual output route. No alternate speech
provider or silent fallback is added. The explicit Test voice remains the only
setup control that can consume ElevenLabs synthesis quota.

Added a hosted iOS Simulator XCTest target with nine native audio regressions:
real session/engine/player completion, local tone, capture-to-playback, queued
stop/retry, late request isolation, provider-vs-native failure, empty/truncated
PCM, interruption recovery and odd/network/newline PCM boundaries. A legacy
option probe records whether the simulator reproduces -50; it is not assumed
identical to physical iOS. Existing 64 core tests are retained.

Version 0.1.3/build 4 retains bundle ID, Keychain, SQLite and provider selections.
Local plist/YAML/XML/Bash checks pass. Run 41316725723 passed all 64 core tests
and native arm64 packaging. Its simulator build attempted x86_64 for the app
while SwiftPM supplied arm64, then failed to import BlackBoxCore. The simulator
script now selects the host architecture explicitly and sets ONLY_ACTIVE_ARCH.
A fresh full run is required; no simulator test execution was claimed for that
failed attempt. Native build and iOS tests for the final source are pending;
do not claim a compiled IPA or live-key playback until the corresponding result
is observed. Continue from this checkpoint and update evidence below.

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

**Native 0.1.2 (build 3) has been compiled, retrieved and preserved for delivery.**

- Repository: https://github.com/Kbryce0902/black-box-ios (owner-authorized public
  repository containing only this project).
- Exact compiled source: `93af30d7d00bf4abc4c6eb959ca92ec64494b636`.
- Successful run: https://github.com/Kbryce0902/black-box-ios/actions/runs/41297291686
  (job 124820695436; all workflow steps succeeded).
- macOS 15.8.2 arm64, Xcode 26.3 (17C529), Apple Swift 6.2.4, iOS 26.2 SDK;
  Release arm64 iphoneos, minimum iOS 17.0.
- **64 tests passed, 0 failures** on that Mac.
- `BlackBox-0.1.2-unsigned.ipa`: 852941 bytes, bundle com.kellen.blackbox.
- IPA SHA-256: `e0a78a247b734ea59cd6b785b72a202e468a35cbe2d50cb87e1a743c709858cb`.
- GitHub artifact 13079872553; outer ZIP SHA-256:
  `6dc1992fcc6e8db5aab6e6f42f39e926fe91dbda68af39d5ff712dde4e22225e`.
- Downloaded outer ZIP and enclosed IPA matched both digests. ZIP, plist,
  executable permissions, arm64 Mach-O and physical iOS platform checks passed
  independently after download.

Install this update over the existing app through SideStore. The owner reports a
previous install/launch; this 0.1.2 update and live ElevenLabs playback are not yet
phone-verified. Saved keys, bundle ID and SQLite location are unchanged. Version
0.1.1 voice/model fields needed Save configuration; use it before updating if
those entries have not been saved. Version 0.1.2 autosaves these fields.

No real provider key, private Voice ID, signing identity or voice material was
uploaded to this repository. No paid provider inference, subscription change or
account-permission change occurred here. Metadata success cannot establish TTS
access, verification, billing or quota; Test voice is the explicit live check.

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
| 04 Voice | Replaceable TranscriptionProvider, Apple finalized captions, streamed ElevenLabs PCM, stop/replay/mute, independent cancellation, routing/interruption handlers | PCM tests and native parser pass. Actual permissions, audio and Bluetooth pending |
| 05 Research/memory | Separate Google-grounded research tool, sources/support markers/rendered attribution, editable memories, per-device aliases | Citation/UTF-8 tests pass; actual grounding and UI attribution acceptance pending |
| 06 Recovery | Transactional claims, no duplicate dispatch/replay, persisted unknown outcomes, saved-call reconciliation on resume, public-client refresh/revocation adapter and reported usage limits | Recovery/cancellation/duplicate/refresh fixtures pass. Native suspension/token/server-revocation tests pending |
| 07 Release | Xcode configuration, actual-build-only unsigned packaging script, SideStore/PC startup instructions and acceptance checklist | Mac arm64 Release build, 64 tests, verified 0.1.2 unsigned IPA PASS; SideStore signing/install and real-device acceptance pending |

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
2. User's ElevenLabs key and accessible authorized target voice ID. Voice creation/owner verification/sharing is separate; see docs/VOICE_SETUP.md. No sample material or target voice was created here.
3. RDC-confirmed public native registration with token auth none, S256, exact callback, mcp:tools scope, advertised resource audience, refresh and supported grant-revocation route.
4. Actual selected Windows PC/agent online after this app's own OAuth consent; helper path and per-device folder aliases; actual Windows, PowerShell, Node and RDC versions.
5. User-side SideStore update to 0.1.2 and native permission/provider checks. A previous install/launch is reported; 0.1.2 Mac compilation is complete.

## Next concrete step

Save any unsaved voice configuration in the existing app, then install 0.1.2
through SideStore over it. Open Settings, run Check voice and model, select the
intended returned model (Eleven v4 uses eleven_v4), then use Test voice. Check the
actual inline ElevenLabs reason if access is refused; never paste the key into
chat or source. Metadata read permissions and Text to Speech permission are
separate. Record actual speech/phone acceptance in docs/ACCEPTANCE.md. Continue
RDC public-native registration separately before claiming phone-to-PC control.
