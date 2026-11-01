# Decisions

| Date | Decision | Reason / consequence |
|---|---|---|
| 2026-11-01 | New native source tree | Workspace inspection found no project source or AGENTS.md. No unrelated work replaced. |
| 2026-11-01 | One SwiftUI app + local portable package | Continuous integration of modules into one product; meaningful core checks on Linux. |
| 2026-11-01 | Direct URLSession integrations; no external iOS SDK | Avoid unverified SDK/platform dependencies and keep clients replaceable. |
| 2026-11-01 | SQLite + Keychain | Durable transactional action journal; credentials kept outside prompts/history. |
| 2026-11-01 | iOS 17 deployment floor, Swift 5 language mode | Uses native APIs available from that floor; target user's actual OS with a suitable current Xcode SDK. |
| 2026-11-01 | Configurable gemini-3.8-flash starting model | Current official model/legacy REST documentation lists support; actual account validation is still required. |
| 2026-11-01 | Search grounding in a separate request | No unverified combination of custom function tools and built-in Search in a single call. |
| 2026-11-01 | RDC native gate remains closed | Live registration ignored requested public auth and returned client_secret_post + secret. No confidential secret embedded. |
| 2026-11-01 | Permit RDC-issued public ID as an explicit setup input | Smallest supported provider configuration change; still must pass independent PKCE/token/device tests. |
| 2026-11-01 | No invented revocation endpoint | Metadata did not advertise one. Expose server revocation only when discovered; local credential deletion is separately labeled. |
| 2026-11-01 | Versioned Windows helper | Avoid unrestricted generated shell code and state claims based merely on process creation. |
| 2026-11-01 | Exact device pinning, serial actions, no automatic mutation retries | Prevent cross-device execution and duplicate side effects after uncertain outcomes. |
| 2026-11-01 | On-resume call-ID retrieval only | Recover observed results without executing stale requests or resuming an interrupted tool loop. |
| 2026-11-01 | Apple finalized speech initially; ElevenLabs output exclusively | Real-device permission/availability checks; transcription can later be replaced without changing execution contracts. |
| 2026-11-01 | Foreground first | No unsupported always-running or silent-audio promise. |
| 2026-11-01 | No repository publication, hosted services or signed build claim | No existing repository or Apple signing environment; no paid activation authorized. |

The Linux SwiftPM test launcher intermittently crashes in this execution host while monitoring `/proc`. A serial build succeeds, and invoking the produced XCTest binary directly succeeds. Both the limitation and the final direct test output are retained. This is a host verification workaround, not an iOS runtime workaround.
# Compilation follow-up — 2026-11-01

- 0.1.2 preserves the chosen Eleven v4 voice/model intent by translating display
  labels to documented API IDs. Metadata model/voice results and actual speech
  remain separate proofs. A failed read-permission check does not block an
  explicit speech test by a key with Text to Speech access.
- The observed metadata HTTP 400 cannot be attributed to a model field the GET
  never sent. Preserve the provider's sanitized reason instead of guessing that
  a key is invalid. No private key or Voice ID from the screenshot enters source.

- 0.1.1 fixes Gemini setup in the existing app. Saving checks metadata
  automatically, with an independent UI deadline, cancellation and explicit
  inline results. Metadata checks never automatically generate paid inference.
- Google model listing and actual inference are separate proofs. Preserve the
  configured model, show returned model IDs, and never silently swap providers
  or claim a successful reply from a metadata response.
- Validation errors retain bounded/redacted Google fields. Keys stay out of
  logs, model context, source and network URLs. Old async results must not change
  state after key replacement/deletion or a deadline.

- The owner authorized the dedicated public GitHub repository on 2026-11-01.
  `Kbryce0902/black-box-ios` is created and verified. Source upload and the 0.1.1 Mac
  build succeeded with 48 tests; exact source/run/digest are in HANDOFF.md.
- Do not reuse AetherMedia or coursework repositories for this app.
- The prepared workflow uses a standard macos-15 runner and Xcode 26.3, runs
  core tests, builds the actual iphoneos target, then validates and uploads the
  unsigned device IPA for the user's SideStore signing workflow.
- The Mac job is skipped in private repositories before runner allocation to
  avoid consuming potentially billable private-runner usage. Artifacts expire
  after one day. No billing setting is changed.
- Packaging verifies arm64 Mach-O executable/platform metadata and emits a
  SHA-256 checksum. These checks do not prove installation or live RDC access.

