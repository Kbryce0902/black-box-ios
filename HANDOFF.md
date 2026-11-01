# Black_Box implementation handoff

Updated 2026-11-01. Source version **0.1.0 development**. Continue this source tree; do not restart from a proposal.

## Compilation request follow-up — 2026-11-01

**Current checkpoint:** The user explicitly authorized creation/publication of
the separate repository. https://github.com/Kbryce0902/black-box-ios was created
and verified public, ID 1441611749, default branch main, initial commit
1131036952ae44498213e73114f177f83ded691d. The GitHub connector confirms push
permission. Upload the source and start the prepared Mac workflow next. No native
compile or IPA has completed yet. Earlier approval-pending notes below describe
the previous checkpoint and are superseded by this authorization.

The user requested an installable IPA. The existing source and its Library bundle
were found in the same workspace; no fresh implementation or materialization was
needed. This host is Linux and has no xcodebuild. The connected RDC device is a
Windows/PowerShell 5.1 desktop with Git and no gh/xcodebuild on PATH. At the earlier
checkpoint, the connected GitHub account had no accessible Black_Box repository.

Prepared in this same app:
- `.github/workflows/build-ios.yml`: standard macos-15/Xcode 26.3, core tests,
  actual unsigned iphoneos compilation and one-day IPA/log artifacts.
- The job skips private repositories before allocating a Mac runner. No private
  minutes, paid service or billing-setting change was authorized or used.
- `Scripts/build-ios.sh`: actual arm64 check, temporary atomic packaging,
  structural verification and SHA-256 checksum.
- `Scripts/verify-ipa.py`: ZIP, plist, execute-bit, arm64 Mach-O and physical iOS
  platform validation. It cannot establish signing or real-device compatibility.
- `.gitignore` and `docs/CLOUD_BUILD.md`: isolated publication/build procedure.

Follow-up checks passed: Bash/Python syntax, YAML configuration/permissions and
private-runner guard; the structural checker accepted one synthetic device
structure and rejected six invalid/source archives. Linux correctly blocks the
actual build with exit 2. The targeted credential scan's sole header match was
the intentional `fixture` redaction test, not an embedded private key. Earlier
34 core tests are retained; unchanged application code was not needlessly retested.

**No native compile or IPA has been produced. No repository has been published.**
The user's original requirement explicitly withholds public publication without
authorization. The concrete proposed route is a separate public
`Kbryce0902/black-box-ios` containing only this project's source. Existing public
AetherMedia source must remain unrelated. The owner must approve this publication
and make the repository available to the connected GitHub integration. No
create-repository capability or authenticated local gh installation was found.

Next step after that repository is available: upload the prepared tree with
`.github` at repository root, run the Mac build, fix actual Apple compiler errors,
retrieve and preserve the exact resulting IPA, then have SideStore re-sign it and
record real installation/launch outcomes. The RDC native-client gate remains
separate and unresolved. See `docs/CLOUD_BUILD.md` for the concrete procedure.

## Current outcome

One native SwiftUI application, one local Swift package, a checked-in Xcode project/shared scheme, Windows helpers, focused tests and setup/release scripts are implemented. The portable core builds and **34 fixture tests pass**. Native Swift/project/script syntax checks pass. No signed or unsigned IPA, Xcode build, simulator run, real phone run, live paid provider call or Windows action has been verified.

**The required RDC feasibility gate is not passed.** Do not describe this as a proven phone-to-PC assistant or a finished release.

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
| 07 Release | Xcode configuration, actual-build-only unsigned packaging script, SideStore/PC startup instructions and acceptance checklist | Linux build script correctly refuses a fabricated IPA. Mac build/signing/installation/acceptance pending |

All modules use the same app, contracts and persistence. The first vertical slice passes only with deterministic fixtures: text → model tool → validation → persisted action → fixture RDC executor → correlated model response. Real YouTube launch is still pending Module 00. Voice is integrated behind that same execution boundary, not evidence that the live slice passed.

## Exact RDC finding

- Official MCP transport: https://mcp.desktopcommander.app/mcp.
- Live protected-resource identifier: https://mcp.desktopcommander.app (origin).
- Authorization metadata advertises S256, authorization_code, refresh_token, `none` and `client_secret_post`; no revocation endpoint was advertised.
- One registration requested application_type=native, token auth `none`, callback `com.kellen.blackbox:/oauth/callback`, authorization_code + refresh_token.
- Response accepted the callback but returned `client_secret_post` and a nonempty secret. Only redacted metadata is in Verification/. The temporary raw registration response was deleted. No secret/client ID was embedded in source and no user grant/token was obtained.
- App rejects this result. Settings accepts a **provider-issued public native client ID** as the smallest supported configuration change to test. Do not add a secret to the app, borrow ChatGPT tokens or introduce a custom backend as a hidden workaround.
- Unknown service response formats fail closed. Capture real, redacted native device/tool/search/helper responses after authentication and refine the versioned adapters as needed.

## Exact checks and versions

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
5. Mac/Xcode/iOS SDK build access and the user's SideStore/signing route; actual iPhone runtime and permissions.

## Next concrete step

Resolve the RDC public-client registration gate with the provider while opening BlackBox.xcodeproj on a suitable Mac. Run core tests, compile the native target, fix any Apple-framework compile issues, then run the integrated Settings harness with user-entered keys and independent RDC consent. Capture redacted real response schemas. Select the PC and validate/test the helper, then prove the YouTube text slice over Wi-Fi and cellular before accepting voice desktop execution. Record each result in docs/ACCEPTANCE.md and this handoff.

No paid services were enabled and no repository was published. Full requirements, setup, contracts, decisions and verified limits are included in the same source bundle.
