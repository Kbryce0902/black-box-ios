# Verified results — 2026-11-01

## Native 0.1.2 IPA build — PASS

- Source: `93af30d7d00bf4abc4c6eb959ca92ec64494b636`.
- Run: https://github.com/Kbryce0902/black-box-ios/actions/runs/41297291686
- macOS 15.8.2 arm64; Xcode 26.3 (17C529), Apple Swift 6.2.4, iOS 26.2 SDK.
- **64 core tests passed, 0 failures**, including 16 new ElevenLabs regressions.
  The earlier 48-test set passed on Linux/macOS for 0.1.1. The transient Linux
  Swift installation expired; no new 0.1.2 Linux execution is claimed.
- Native Release arm64 iphoneos build, packaging and structural checks PASS.
- `BlackBox-0.1.2-unsigned.ipa`: 852941 bytes, build 3, minimum iOS 17.0.
- SHA-256: `e0a78a247b734ea59cd6b785b72a202e468a35cbe2d50cb87e1a743c709858cb`.
- Downloaded GitHub ZIP digest and enclosed IPA checksum both matched; local
  structural verification passed again after download.
- Existing Apple speech/Swift 6-mode compatibility warnings remain non-fatal.
- No live ElevenLabs key/synthesis result was available here. The generic HTTP
  400 in the owner's screenshot discarded its reason in the previous app;
  normalization fixes the confirmed model-ID bug but does not prove the cause
  of a metadata GET that never sent the model field.
- Actual 0.1.2 phone playback, headset routes and provider account access remain
  pending. RDC public-native registration is separately blocked.

## Initial local checks

| Check | Environment | Actual result |
|---|---|---|
| Core build including tests | Ubuntu 24.04 x86_64, Swift 6.0.3, Swift 5 language mode | PASS; build output in core-build.log |
| XCTest binary | Same Linux host; deterministic fixtures, no provider credentials | **34 tests, 0 failures**; core-direct-tests.log |
| iOS Swift parser | Swift frontend, Linux, all seven native Swift files | PASS; ios-syntax.log empty (no diagnostics). **Syntax only**, no Apple framework typecheck |
| Xcode project structure | OpenStep parser; object references, source inclusion, plist and scheme XML | PASS; project-structure.log. **Not an Xcode build** |
| Windows helper syntax | PowerShell 7.4.6 parser on Linux | PASS; powershell-syntax.log. **No Windows actions executed** |
| Build shell/Python scripts | Bash syntax, Python compilation | PASS |
| Real iOS build availability | Linux; build-ios.sh simulator | BLOCKED correctly with exit 2: Xcode/Apple SDK required; no placeholder IPA |
| RDC public discovery | Unauthenticated HTTPS | Received live metadata; initial alternate HTTP path returned 403 |
| RDC native registration | One unauthenticated dynamic registration request | **FAIL for public native client**: callback echoed, but client_secret_post and a nonempty secret returned. Redacted snapshot retained |
| Gemini inference / ElevenLabs audio | No user keys supplied | NOT RUN |
| Independent RDC consent/token/device tools | No supported public registration or native user consent | NOT RUN |
| Simulator / real iPhone / cellular | No Apple SDK/device/signing environment | NOT RUN |
| Actual Windows helpers, media, files, metrics | No independently authenticated app-to-PC route | NOT RUN |

## What the fixtures prove

Validation rejects extra device/shell arguments, unsupported URLs/apps, traversal and credential paths. It pins aliases to one device and keeps public research available without a PC. Parsers retain split UTF-8, PCM sample tails, opaque JSON, thought signatures and function call IDs; malformed/truncated streams fail closed. OAuth tests reject confidential registrations and bad callbacks, and check refresh audience/fallback behavior without live tokens.

The simulated YouTube slice observes an action record before executor dispatch and returns the matching function response to the fixture model. Duplicate dispatch, cancellation before a second call, unknown timeout, interrupted SQLite recovery, known remote failure correlation and invalid-tool errors have focused checks. Credential-excerpt redaction is tested. These are deterministic local checks, not provider/device success.

## Host launcher limitation

The initial default parallel Swift build and SwiftPM test launcher intermittently terminated with an illegal instruction while the execution environment monitored /proc. A serial `swift build --build-tests --jobs 1 -Xswiftc -disable-batch-mode` completed, followed by direct execution of the built XCTest binary in a separate shell invocation. The final successful output is retained; the failed launcher output is under attempts/. This workaround does not validate an iOS runtime.

The temporary Linux toolchain and locally extracted development headers/libraries are not included in the source ZIP. Standard Mac/Xcode environments can run `swift test --jobs 1` directly. No service subscription or real API inference was performed. The separate public repository was subsequently created with owner authorization and used for the successful Mac compilation above.
