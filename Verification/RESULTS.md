# Verified results — 2026-11-01

## Native IPA build — PASS

- Source: `9cec8dcfbad11e0d402f0e566f91a9e9c5d440d3`.
- Run: https://github.com/Kbryce0902/black-box-ios/actions/runs/41291008404
- macOS 15.8.2 arm64; Xcode 26.3 (17C529), Apple Swift 6.2.4, iOS 26.2 SDK.
- **48 core tests passed, 0 failures** on Linux and macOS. The 14 new regressions
  exercise the production Gemini validation controller, pagination, HTTP failures,
  deadlines, retry and stale-response rejection.
- **Native Release iphoneos build succeeded.** No Swift compiler errors.
- Packaging and structural verification passed on the Mac and after download.
- `BlackBox-0.1.1-unsigned.ipa`: 818342 bytes, build 2, arm64, minimum iOS 17.0.
- SHA-256: `22179321120c3ddfbce778c93d273c92103170e239caaef5c9f6fc086a5be55e`.
- Downloaded GitHub artifact ZIP digest and enclosed IPA checksum both matched.
- The owner reports 0.1.0 installed and launches. 0.1.1 SideStore update acceptance,
  simulator execution, actual phone/provider/cellular
  and app-to-Windows integration remain NOT RUN. RDC registration remains BLOCKED.

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
