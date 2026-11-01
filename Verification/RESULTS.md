# Verified results — 2026-11-01

## IPA compilation follow-up

- Current host: Linux, no xcodebuild. The updated `build-ios.sh unsigned` exits
  with the expected code 2; no native compilation or IPA occurred.
- Bash syntax, Python compilation and GitHub workflow YAML/configuration checks:
  PASS. The workflow's public-repository job guard is present before allocation.
- IPA structural checker: one synthetic arm64-device structure accepted and six
  invalid archives rejected (simulator plist, simulator binary, missing execute
  mode, missing app payload, truncated load commands and the actual source ZIP).
  These are packaging fixtures, not a compiled or installable app.
- A targeted credential scan flags the deliberate `fixture` private-key-header
  redaction test. That is test data; no real private key is stored there.
- No Black_Box repository is visible to the connected GitHub account. The sole
  connected RDC device is Windows/PowerShell 5.1, with no gh or xcodebuild on PATH.
- GitHub Mac execution, Apple-framework compilation, signing, SideStore install
  and live RDC access all remain NOT RUN. See `docs/CLOUD_BUILD.md`.

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

The temporary Linux toolchain and locally extracted development headers/libraries are not included in the source ZIP. Standard Mac/Xcode environments can run `swift test --jobs 1` directly. No service subscription, real API inference or repository publication was performed.
