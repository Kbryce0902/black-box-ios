# Module 00 — feasibility and provider evidence

Checked 2026-11-01. This is evidence of documentation and unauthenticated discovery, not an authenticated native acceptance result.

## RDC: gate not passed

Official endpoint: `https://mcp.desktopcommander.app/mcp` (Streamable HTTP). Official setup documents OAuth/PKCE and a paired desktop agent. That establishes the intended protocol, not support for this particular native registration.

Live public metadata was retrieved after initial 403 responses from another HTTP path. It advertises S256, authorization_code, refresh_token, token authentication `none` and `client_secret_post`, and a registration endpoint. The protected resource identifier is the origin `https://mcp.desktopcommander.app`, distinct from the `/mcp` transport URL. No token revocation endpoint was advertised.

One registration probe submitted JSON with:

```json
{
  "client_name": "Black_Box Native Feasibility",
  "application_type": "native",
  "redirect_uris": ["com.kellen.blackbox:/oauth/callback"],
  "grant_types": ["authorization_code", "refresh_token"],
  "response_types": ["code"],
  "token_endpoint_auth_method": "none"
}
```

The response echoed the callback and grants but returned `token_endpoint_auth_method: client_secret_post` and a client secret. Only redacted metadata was saved. No user authorization, token exchange or account tool call was performed by this custom client.

**Conclusion:** this dynamic-registration path did not prove a secret-free native client. It does not prove that all RDC public-client configurations are impossible. The app deliberately refuses the returned confidential client. Its Settings screen also accepts a public client ID explicitly provisioned by RDC, which still needs live verification.

**Smallest supported change to investigate:** RDC provisions or fixes a public native registration with PKCE S256, token endpoint auth `none`, exact callback `com.kellen.blackbox:/oauth/callback`, least scope `mcp:tools`, refresh support and the advertised resource audience. Obtain its supported grant-revocation route. No cloud backend has been substituted. If RDC confirms public clients are unsupported, the user must choose whether to change provider or authorize another architecture; current code does neither silently.

The app never reads ChatGPT connector credentials. A previously paired device/account may be reused only after this app receives its own authorization grant.

## Gemini

Official documentation currently lists `gemini-3.8-flash` as a stable model with function calling and Search grounding. This is a configurable starting value; account availability is verified in the harness with the model-list API before inference. The client uses the still-documented `v1beta/models/{model}:streamGenerateContent?alt=sse` REST route and `x-goog-api-key` header, not an SDK or consumer app. The documentation labels generateContent as legacy; a replaceable ReasoningClient boundary permits a later Interactions migration.

Complete content parts are retained across streamed responses and persisted before tools run, including encrypted thought signatures and call IDs. Custom function tools and Google Search use separate requests; mixed-tool compatibility is not assumed. `research_web` works with no selected PC. Grounding metadata, source links, byte-indexed support markers and rendered search attribution are retained. Real model, citations and quota behavior remain untested without a key.

## ElevenLabs

The direct `POST /v1/text-to-speech/{voice_id}/stream?output_format=pcm_24000` adapter uses a configurable voice/model and `xi-api-key`. Raw signed little-endian PCM is decoded across arbitrary byte boundaries and played by AVAudioEngine. No Google/Apple synthesized fallback voice is used. Playback has not been listened to on an iPhone. Voice setup is independent: see [VOICE_SETUP.md](VOICE_SETUP.md).

## Apple / installation

The native deployment floor is iOS 17 because the app uses iOS 17 SwiftUI APIs. Source is compiled in Swift 5 language mode with a Swift-tools 5.9 package manifest. The portable core was actually compiled with Swift 6.0.3 on Ubuntu 24.04 x86_64. This does not validate Apple framework calls.

Apple's current compatibility table lists Xcode 27.1 with iOS 27.1 SDK and macOS Tahoe 26.6 or later; check the current table and actual machine before building. There is no Mac, Xcode, Apple SDK, signing identity or connected phone here. The app's harness displays the actual `hw.machine` identifier and runtime OS/build; a marketing device name and prior user-agent string are not hardware verification. No iPhone 18 Pro Max simulator or SideStore result is claimed.

SideStore's official installation guide covers pairing, trust, Developer Mode and its refresh workflow. This app needs no JIT or special background entitlement. Re-signing and the OAuth callback still require actual testing on the user's OS/device. No IPA exists until a real `iphoneos` build succeeds.

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
