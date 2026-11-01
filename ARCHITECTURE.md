# Architecture

## Runtime ownership

The SwiftUI iPhone app owns conversation, durable task state, provider credentials, audio, memory and tool orchestration. `BlackBoxCore` is a portable Swift package. It compiles independently of Apple UI frameworks so policy and wire handling can be tested on Linux. Native adapters use Apple frameworks only; there are no third-party iOS SDK dependencies.

| Component | Responsibility |
|---|---|
| AppModel | Integrates one conversation, explicit PC selection, Settings, diagnostics and recovery |
| ConversationEngine | Saves model continuations and serially executes validated function calls within task limits |
| Repository | SQLite WAL journal; atomic turn commitment and action claims |
| GeminiClient | Direct REST/SSE, complete content parts, grounding metadata and reported usage |
| DesktopExecutor | Live schema/device checks, bounded excerpts, fixed helper calls and search-session ownership |
| MCPClient | JSON-RPC correlation, initialization, negotiated protocol and session headers |
| RDCSession / OAuthClient | Independent ASWebAuthenticationSession + PKCE, public client gate and serialized refresh |
| AudioController / ElevenLabsClient | Finalized Apple recognition, PCM streaming, interruption and generation invalidation |
| KeychainStore | Provider keys, independent OAuth credentials and public registration metadata |

Public research calls Gemini directly. An online PC is required only for desktop tools. RDC's hosted relay is the existing provider service, not a newly introduced backend.

## Commit and execution ordering

1. Commit a user message and queued task in one SQLite transaction.
2. Retrieve bounded complete history turns, matching memories and aliases for the pinned device ID.
3. Stream Gemini response. Display text deltas, but execute no partial function arguments or speech transcripts.
4. Require a complete STOP response. Persist all original content parts, including opaque metadata.
5. Validate the exact function/argument set, path roots, helper gate and device ID. Reject extra `deviceId` or shell-code arguments supplied by the model.
6. Review new folder/file moves with concrete arguments; routine allowed reads/launches/media do not prompt again.
7. Claim an immutable action in a SQLite transaction before dispatch. Duplicate call IDs and repeated identical actions in the same task are rejected.
8. Check the selected device's current reported availability and live RDC schema. Execute serially. Helpers receive base64 JSON data through a fixed PowerShell command; no model-generated script is accepted.
9. Store observed result, failure or unknown state. A complete helper result marker is required to count a helper action as completed. Process creation by itself is uncertain.
10. Return all correlated function responses as one user content block after the full model content block. Continue within limits.
11. Save final assistant text and sources; stream ElevenLabs speech independently. Stopping audio does not cancel execution.

## Research

`research_web` is a custom local orchestrator function. It makes a separate Gemini request with only Google Search grounding, preserving source supports and rendered attribution. The model chooses when to research; no PC browser is involved. This avoids relying on model-specific combinations of built-in and custom tools. Only HTTP(S) source links are rendered. The attribution web view has no JavaScript, cookies shared with the native client, native message handlers or tool access.

## Desktop boundaries

The user selects a specific RDC device. Each desktop action retains that ID even if UI state changes. Only a live Windows helper handshake enables desktop declarations; the handshake expires on app backgrounding or selection/path changes. The helper refuses junction/reparse paths, supports a fixed application/media allowlist, measures real RAM/process values, and never overwrites a file destination. Read/search paths are preflighted before RDC file tools. Common credential paths are excluded and excerpts receive additional credential-pattern redaction.

Search result pagination accepts only a session created by this task on the same device. Unknown provider response shapes are not guessed. Production device/search/helper response adapters still require the native feasibility test against the user's independently authorized account.

## Interruption and recovery

Cancellation changes durable task state before cancelling the Swift task. Future dispatch checks fail. Already completed actions remain recorded; stopping local work does not terminate RDC or undo a remote process. A network failure after a claim leaves the action unknown. Known remote rejection is returned as failure. Mutations are never automatically replayed on 401, MCP session expiry, timeout or reconnection.

On backgrounding the app cancels local dispatch/audio and invalidates helper readiness. On launch/resume, running actions become unknown and queued/waiting work becomes blocked. The app refreshes account/device presence. Where an existing call ID and retrieval tool exist, it reads that call and records the result; it never repeats the original operation. If all uncertain calls resolve, the interrupted task becomes blocked for inspection instead of silently resuming the Gemini loop.

## Limits

The initial release operates in the foreground. There is no silent audio keepalive, always-on wake word, scheduled background execution, arbitrary browser clicking or screen-control claim. Usage is a bound on steps, dispatch window and reported tokens, not a prepaid billing guarantee; a provider response can consume quota before the app sees its usage. Prior history uses complete turns within a byte ceiling. Speech has a configurable character ceiling. Network responses are size-bounded.

Swift language mode remains 5 for a manageable compatibility baseline. Full iOS framework typechecking and real audio/OAuth behavior are pending Xcode and device access; portable compilation does not cover those adapters.
