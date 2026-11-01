# Acceptance checklist — real results required

Statuses below distinguish completed compilation from pending real-device checks. Fill in actual device ID, OS/build, runtime/package versions, date, network and observed result after running them. Do not convert a portable fixture result to a live pass.

| Check | Required observation | Status |
|---|---|---|
| Native device build | Release arm64 iphoneos compile; compiler/SDK versions recorded | PASS — Xcode 26.3, Swift 6.2.4, iOS SDK 26.2, run 41337372895 |
| Simulator | Hosted app session/engine/player execution with local PCM | PASS — 11 native tests (nine audio, two Keychain) on arm64 iOS 26.2; physical hardware acceptance remains separate |
| IPA packaging | Physical iOS Mach-O, ZIP integrity and exact downloaded checksums | PASS — 0.1.5, 940422 bytes; SHA-256 in HANDOFF.md |
| Phone identity | Runtime hw.machine and OS/build; actual target confirmed | PENDING |
| SideStore | Re-signed install, launch and refresh on actual OS | 0.1.4 install, launch and RDC login reported working by owner; 0.1.5 command acceptance pending |
| Gemini setup feedback | Save starts checking; errors/deadline replace progress; returned model can be selected | 48 tests PASS on Linux and macOS including 14 Gemini regressions; real-key verification pending |
| Gemini direct | Native API response with user's key and selected model | PENDING |
| ElevenLabs | Audible streamed reply using configured authorized voice ID | 64 core and nine native audio tests PASS; owner reported 0.1.2 metadata access but native -50; 0.1.3 actual speech pending |
| ElevenLabs setup | Canonical model, voice correlation, redacted errors, deadline and independent TTS test | 0.1.2 real voice/model metadata success reported by owner; native Test voice failed with OSStatus -50; 0.1.3 native repair compiled and simulator-tested; phone acceptance pending |
| RDC registration | Supported per-install method, exact callback and protected credentials | Live DCR HTTP 200/callback observed; 81 core and 11 native tests PASS; owner now reports successful native browser login and connected-PC display |
| RDC callback | Independent system-browser PKCE/state validation and code exchange | Native sign-in success reported by owner; refresh/revoke are separate pending tests |
| Refresh | Expired access token refresh, rotation preserved, concurrent refresh serialized | PENDING |
| Revocation | Supported server grant revocation; later tool access refused | PENDING; no endpoint advertised |
| Device selection | Paired listing; explicit selection; two-device targeting stays pinned | Owner reports a selected online PC; two-device targeting remains pending |
| Helper readiness | Default discovery, valid capabilities, background recheck, visible setup reason and current model tools | 94 core tests PASS including 13 desktop regressions; connector capabilities/default discovery PASS on Windows 10 / PowerShell 5.1; native 0.1.5 phone check pending |
| Text YouTube slice | iPhone text → Gemini → validation → saved action → RDC → selected PC → result → correlated Gemini response | PENDING |
| Launch evidence | UI distinguishes accepted URL launch from an observed loaded page | PENDING |
| PC offline | Fresh conversation + public research succeed; desktop tools blocked, no delayed launch | PENDING |
| Cellular | Wi-Fi off on phone; independently authorized call reaches selected awake PC | PENDING |
| Files | Literal search, existing session pagination, safe read/excerpt and phone summary of TXT/MD/PDF/DOCX | PENDING |
| Aliases | Separate projects/school/downloads roots on each selected PC; traversal/junction rejection | PENDING |
| Resource use | Actual UTC timestamp, total/free/used bytes, process working sets and CPU interval | PASS through separate RDC connector; native phone request pending |
| File operations | Temp-folder test passes; destination never overwritten; reviewed move observed | PENDING |
| Media | Pause command acknowledged and actual chosen player inspected separately | PENDING |
| Captions | Partial phrases visible but zero dispatch; finalized turn committed once | PENDING |
| Audio routing | Speaker, wired/headset/Bluetooth switch, incoming-call interruption and resume | PENDING |
| Stop vs cancel | Speech stop leaves task unaffected; task cancellation prevents next dispatch without undo claims | PENDING |
| Network/quota | Mid-response disconnect, 401/429/quota errors; no duplicate mutation POST | PENDING |
| Recovery | Suspend/force-close after claim; unknown shown; existing call retrieval; no stale replay | PENDING |
| History/memory | Relaunch retains chat; edit/delete memories; relevant retrieval and independent per-device aliases | PENDING |
| Privacy | Key inputs clear/mask; Keychain removal works; logs/model context exclude credentials | PENDING |

Record the Windows helper script's separate acceptance output with Windows build, PowerShell version and actual RDC/Node versions. Linux parsing of that script is not a Windows test. A successful helper handshake is capability discovery, not evidence that every operation has passed acceptance.

## First real integration session

1. Update the existing SideStore app to 0.1.5; preserve its app identity and native RDC login.
2. Keep the paired PC awake with RDC running. In Computer, select that PC and wait for PC ready. Use Find and check helper if needed; a blank path discovers LocalAppData/BlackBox-iOS/BlackBoxHelper.ps1.
3. Send a fresh request: "Measure my current RAM usage." Confirm Activity contains inspect_resources and the reply cites actual timestamp/units.
4. Background and reopen the app. Confirm the helper check returns to PC ready; request another fresh measurement. Old requests must not run automatically.
5. Send the YouTube text request and separately observe its actual browser effect. Repeat over cellular, then test finalized voice on the proven path.

The native device build and package checks succeeded. The owner reports successful installation and real metadata access in 0.1.2, followed by the native speech error described above. New-version device playback remains to be recorded.
