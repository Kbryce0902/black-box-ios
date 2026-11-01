# Acceptance checklist — real results required

Statuses below distinguish completed compilation from pending real-device checks. Fill in actual device ID, OS/build, runtime/package versions, date, network and observed result after running them. Do not convert a portable fixture result to a live pass.

| Check | Required observation | Status |
|---|---|---|
| Native device build | Release arm64 iphoneos compile; compiler/SDK versions recorded | PASS — Xcode 26.3, Swift 6.2.4, iOS SDK 26.2, run 41288398459 |
| Simulator | Simulator compile and execution | PENDING |
| IPA packaging | Physical iOS Mach-O, ZIP integrity and exact downloaded checksums | PASS — 783221 bytes; SHA-256 in HANDOFF.md |
| Phone identity | Runtime hw.machine and OS/build; actual target confirmed | PENDING |
| SideStore | Re-signed install, launch and refresh on actual OS | 0.1.0 install and launch reported by owner; refresh and 0.1.1 acceptance pending |
| Gemini setup feedback | Save starts checking; errors/deadline replace progress; returned model can be selected | 48 portable tests PASS including 14 Gemini regressions; real-key verification pending |
| Gemini direct | Native API response with user's key and selected model | PENDING |
| ElevenLabs | Audible streamed reply using configured authorized voice ID | PENDING |
| RDC registration | Public native registration, no secret, exact callback | BLOCKED by tested DCR result |
| RDC callback | Independent system-browser PKCE/state validation and code exchange | PENDING |
| Refresh | Expired access token refresh, rotation preserved, concurrent refresh serialized | PENDING |
| Revocation | Supported server grant revocation; later tool access refused | PENDING; no endpoint advertised |
| Device selection | Paired listing; explicit selection; two-device targeting stays pinned | PENDING |
| Text YouTube slice | iPhone text → Gemini → validation → saved action → RDC → selected PC → result → correlated Gemini response | PENDING |
| Launch evidence | UI distinguishes accepted URL launch from an observed loaded page | PENDING |
| PC offline | Fresh conversation + public research succeed; desktop tools blocked, no delayed launch | PENDING |
| Cellular | Wi-Fi off on phone; independently authorized call reaches selected awake PC | PENDING |
| Files | Literal search, existing session pagination, safe read/excerpt and phone summary of TXT/MD/PDF/DOCX | PENDING |
| Aliases | Separate projects/school/downloads roots on each selected PC; traversal/junction rejection | PENDING |
| Resource use | Actual UTC timestamp, total/free/used bytes, process working sets and CPU interval | PENDING |
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

1. Resolve the public-client registration blocker with RDC.
2. Build and install on the phone. Run the three native provider harness checks.
3. Verify the existing paired PC and install/test the reviewed helper.
4. Select that device, check the helper, send the YouTube text request and record each observed result.
5. Repeat over cellular; only then test finalized voice on the proven path.

The native device build and package checks succeeded. No actual iPhone installation or real-device result is available yet.
