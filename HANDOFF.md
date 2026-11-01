# Black_Box implementation handoff

Updated 2026-11-01. Source version **0.1.1 development**. Continue this repository;
do not restart from a proposal.

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
key redaction. Native syntax and shell/YAML/version checks PASS. Native Mac
compilation of 0.1.1 is the next step. No user API key or live Google success was
available here; do not substitute fixture results for that proof.

Official references checked 2026-11-01:
https://ai.google.dev/api/models
https://ai.google.dev/gemini-api/docs/models/gemini-3.8-flash
https://ai.google.dev/gemini-api/docs/api-key

The release evidence below is the earlier 0.1.0 build until the 0.1.1 Mac run is
completed and recorded.

## Current outcome

**A native arm64 iPhone IPA has been compiled and retrieved.**

- Repository: https://github.com/Kbryce0902/black-box-ios (public; explicitly
  authorized by the owner). Only this project's files were uploaded.
- Exact compiled source: `dbec5b93dd1d20e209462f5c7076871c1970cb34`.
- Successful run: https://github.com/Kbryce0902/black-box-ios/actions/runs/41288398459
  (job 124794338839, all workflow steps succeeded).
- Environment: macOS 15.8.2 arm64, Xcode 26.3 (17C529), Apple Swift 6.2.4,
  iOS 26.2 SDK, Release configuration, deployment floor iOS 17.0.
- Core tests on that Mac: **34 passed, 0 failures**.
- Artifact: `BlackBox-0.1.0-unsigned.ipa`, 783221 bytes,
  bundle `com.kellen.blackbox`, physical `iphoneos` platform, arm64 executable.
- IPA SHA-256: `3376bb2827ea7ff468d303b11f5d1a8abec109a572d3a2222c0371ab7c71505c`.
- GitHub artifact ID 13076082585; outer ZIP digest
  `e4f67885d772d62ce49f1466120c02d644b02f395c6487be24d32ecd23cbe9d4`.
  The downloaded outer artifact and enclosed IPA both matched their checksums.
  Structural verification also passed independently after download.

**Import this IPA into SideStore to sign and install it.** No Apple signing
identity or profile was requested, embedded or uploaded. Signing, actual phone
installation/launch, simulator execution, paid provider inference and live
app-to-Windows actions remain unverified. Do not call this a finished assistant.

**The required RDC native authentication feasibility gate is still unresolved.**
The existing confidential-client registration finding is unchanged below.

## Compilation changes and checkpoints

1. Created the dedicated public repository after explicit owner authorization.
2. Run 41288013816 passed 34 tests but could not find the Xcode project because
   the upload manifest omitted that existing directory. Commit
   `a6e1523ddd710c9f794367e081e2f9fdfd4b284e` added the project and shared scheme.
3. Run 41288221772 compiled the native app successfully but packaging failed
   because lipo -verify_arch was passed the input in the wrong position.
4. Commit `dbec5b93dd1d20e209462f5c7076871c1970cb34` corrected the argument order.
   Run 41288398459 passed compilation, packaging, verification and upload.
5. Source/header documentation updates after that commit do not alter the binary.

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
| 07 Release | Xcode configuration, actual-build-only unsigned packaging script, SideStore/PC startup instructions and acceptance checklist | Mac arm64 Release build, 34 tests, verified unsigned IPA PASS; SideStore signing/install and real-device acceptance pending |

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
5. User-side SideStore re-signing/install, actual iPhone runtime and permissions. Mac compilation is complete as recorded above.

## Next concrete step

Import the delivered IPA into SideStore and record installation, launch and
permission results in docs/ACCEPTANCE.md. Enter the user's Gemini/ElevenLabs keys
only in native Settings and run the integrated provider harness. Resolve RDC's
public native client registration with the provider; then verify independent
OAuth, actual device/tool schemas and the helper before attempting the YouTube
text slice over Wi-Fi and cellular. Keep the authentication gate closed until
those checks succeed. No completed desktop action or voice quality is implied
by successful compilation.
