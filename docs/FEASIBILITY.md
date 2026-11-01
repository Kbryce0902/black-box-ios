# Module 00 — feasibility and provider evidence

Checked 2026-11-01. This is evidence of documentation and unauthenticated discovery, not an authenticated native acceptance result.

## RDC: per-install compatibility implemented in 0.1.4; live grant pending

Official endpoint: `https://mcp.desktopcommander.app/mcp` (Streamable HTTP).
The app discovers its resource origin and requires external browser sign-in,
PKCE S256, exact callback `com.kellen.blackbox:/oauth/callback`, state validation
and the `mcp:tools` scope. It does not reuse ChatGPT connector credentials.

The earlier 0.1.0–0.1.3 gate accepted only a secret-free registration. Live RDC
registration instead returns `client_secret_post` plus a new credential for that
registration and echoes the exact callback. Rejecting every such result was an
unnecessarily restrictive client policy: RFC 8252 section 8.4 explicitly allows
DCR to issue per-instance native credentials; section 8.5 distinguishes those
from a shared secret embedded in a distributed binary.

0.1.4 implements the returned, advertised method (none/post/basic) with per-install
credentials in device-only Keychain. No credential is embedded in source or IPA.
Authorization still requires browser consent, state and PKCE; token, refresh and
supported revocation calls authenticate the registered installation over HTTPS.
Registration/token grants are stored atomically; pending registration is separate
from an already connected account. Legacy public grants migrate without new keys.

Current public metadata and one live, unauthenticated registration were checked
on 2026-11-01. Only whitelisted noncredential results are preserved in
Verification/rdc-compatibility-0.1.4.json. Authorize and an invalid-code token probe
returned HTTP 403 from this execution environment. No user code/access token or
independent Black_Box device action was obtained. A working existing ChatGPT
connection and an online PC are not proof of Black_Box's own grant.

RDC's observed list_devices text output now has a strict UUID/status adapter in
addition to structured JSON. Ambiguous records are rejected. Selection, capability
handshake and actual helper action acceptance remain separate steps.

No cloud backend, alternate provider, account-permission change or billing change
has been substituted. The next live check is Settings → Sign in with PKCE on the
owner's phone, then Computer → Refresh paired devices and select the computer.

Standards and primary implementation references:
- https://www.rfc-editor.org/rfc/rfc8252.html#section-8.4
- https://www.rfc-editor.org/rfc/rfc7591.html
- https://github.com/modelcontextprotocol/python-sdk/blob/main/docs/migration.md

## Gemini

Official documentation currently lists `gemini-3.8-flash` as a stable model with function calling and Search grounding. This is a configurable starting value; account availability is verified in the harness with the model-list API before inference. The client uses the still-documented `v1beta/models/{model}:streamGenerateContent?alt=sse` REST route and `x-goog-api-key` header, not an SDK or consumer app. The documentation labels generateContent as legacy; a replaceable ReasoningClient boundary permits a later Interactions migration.

Complete content parts are retained across streamed responses and persisted before tools run, including encrypted thought signatures and call IDs. Custom function tools and Google Search use separate requests; mixed-tool compatibility is not assumed. `research_web` works with no selected PC. Grounding metadata, source links, byte-indexed support markers and rendered search attribution are retained. Real model, citations and quota behavior remain untested without a key.

## ElevenLabs

The direct `POST /v1/text-to-speech/{voice_id}/stream?output_format=pcm_24000` adapter uses a configurable voice/model and `xi-api-key`. Raw signed little-endian PCM is decoded across arbitrary byte boundaries and played by AVAudioEngine. No Google/Apple synthesized fallback voice is used. Playback has not been listened to on an iPhone. Voice setup is independent: see [VOICE_SETUP.md](VOICE_SETUP.md).

## Apple / installation

The native deployment floor is iOS 17 because the app uses iOS 17 SwiftUI APIs. Source is compiled in Swift 5 language mode with a Swift-tools 5.9 package manifest. The portable core was actually compiled with Swift 6.0.3 on Ubuntu 24.04 x86_64. This does not validate Apple framework calls.

Actual compilation uses a public GitHub Mac runner: Xcode 26.3, Swift 6.2.4 and
iOS 26.2 on macOS 15.8.2, with native simulator execution. This workspace has no
connected iPhone or physical-device signing identity. The owner reports prior
SideStore installs and 0.1.3 mostly working; 0.1.4 physical acceptance is pending.
The native harness can report hw.machine and the actual OS/build; an inferred
marketing name is not hardware verification. See HANDOFF.md for exact evidence.

SideStore's official installation guide covers pairing, trust, Developer Mode and its refresh workflow. This app needs no JIT or special background entitlement. Re-signing and the OAuth callback still require actual testing on the user's OS/device. A real arm64 IPA was compiled and delivered for earlier releases; each new version still requires its own successful native build and structural verification.

## Primary sources

- RDC official README: https://github.com/desktop-commander/remote-desktop-commander
- RDC setup: https://github.com/desktop-commander/remote-desktop-commander/blob/main/docs/SETUP.md
- Live discovery snapshots: `Verification/rdc-authorization-metadata.json`, `rdc-resource-redacted.json`, `rdc-registration-redacted.json`
- MCP authorization: https://modelcontextprotocol.io/specification/2025-06-18/basic/authorization
- Gemini model: https://ai.google.dev/gemini-api/docs/models/gemini-3.8-flash
- Gemini legacy REST grounding: https://ai.google.dev/gemini-api/docs/generate-content/google-search
- Gemini thought signatures: https://ai.google.dev/gemini-api/docs/generate-content/thought-signatures
- ElevenLabs HTTP stream: https://elevenlabs.io/docs/api-reference/text-to-speech/stream
- Apple compatibility: https://developer.apple.com/xcode/system-requirements/
- SideStore installation: https://docs.sidestore.io/docs/installation/install
