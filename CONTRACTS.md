# Contracts v1

## Durable records

| Entity | Identity / required data |
|---|---|
| TaskRecord | UUID, committed input, pinned optional device ID, state, timestamp, opaque wire history, reported tokens |
| ActionRecord | UUID, task UUID, provider call ID or stable step:index, name, validated arguments, pinned device ID, state, timestamp, optional RDC call ID/result |
| ChatMessage | UUID, task UUID, role, text, timestamp, source links and required rendered attribution |
| FolderAlias | device ID + normalized name; absolute Windows drive path |
| Memory | UUID and user-editable local text |

States are `queued`, `running`, `waiting_for_user`, `blocked`, `completed`, `failed`, `cancelled`, `unknown`. No state implies a remote undo. A completed action represents the evidence recorded for that operation; a URL launch acknowledgement does not establish browser page load.

Repository uses the operating-system SQLite library, parameter binding, WAL and transactions. User turn/task commitment and action-claim checks are atomic. Credentials are absent from its schema. App data is protected on the iPhone and excluded from backup in this initial version. No automatic database reset occurs on decode/open errors.

## Provider protocols

- `ReasoningClient.generate`: complete history and tool declarations in; streamed user-visible deltas plus complete content parts, grounding and reported usage out. Unknown JSON part fields and signature locations must survive round trips.
- `HTTPClient`: bounded authenticated REST/stream transport, no credential forwarding through redirects; fixture implementation is test-only.
- `ToolExecutor.execute`: accepts only a ValidatedTool, returns observed JSON, optional sources, pending remote ID and explicit success/failure. No raw generated shell command is accepted by policy.
- `SpeechClient.audio`: text in, cancellable raw PCM16 24 kHz mono bytes out for ElevenLabs. Odd-byte network boundaries must be preserved.
- `MCPClient`: correlate JSON-RPC IDs, negotiate supported protocol versions, retain session header, fail closed on mismatch. Do not automatically repeat POSTs.

## Tools

| Local function | Arguments | Remote behavior |
|---|---|---|
| research_web | query | Separate grounded Gemini request; no device |
| open_url | url | Fixed helper, HTTP(S) only |
| open_alias | alias | Resolve a folder for the pinned device, then helper |
| open_path | path | Alias-root-contained supported file/folder launch |
| open_application | application | notepad, calculator, explorer, chrome, edge |
| search_files | alias, query | Helper path preflight; literal RDC start_search, bounded results |
| search_more / search_stop | session_id | Existing task/device-owned session only |
| read_file | path | Helper path preflight; supported bounded RDC document excerpt |
| inspect_resources | none | Actual Windows measurement in bytes with UTC timestamp and sampling interval |
| media_control | command | pause, play_pause, next, previous; acknowledgement only |
| create_folder | path | Explicit review, no overwrite, observed existence |
| move_file | source, destination | Explicit review, no overwrite, observe both paths |

Tool argument keys must match the declared set exactly. The app supplies `deviceId`, which is never model-controlled. Paths reject UNC/device forms, traversal, alternate data streams, ambiguous components and common credential files. Aliases are local configuration data, not shell fragments. File excerpts are capped and treated as untrusted data.

## Windows helper protocol

Input is base64-encoded UTF-8 JSON: `{version:1, operation, arguments, roots}`. It is passed as an argument to a user-installed `BlackBoxHelper.ps1` through a fixed encoded PowerShell invocation. RemoteSigned applies only to that process and cannot override domain Group Policy. No admin rights or global execution-policy change is requested.

A terminal result is one complete JSON line with `marker: BLACKBOX_HELPER_V1`, matching operation, `ok`, `observedAt` and operation-specific evidence. A successful capabilities line also contains `os: Windows`, actual OS version and PowerShell runtime. Missing/truncated result marker means unknown, even if a process was started. Actual Windows helper acceptance results are pending; syntax-only validation is not acceptance.

## Recovery and permission invariants

- Persist intent before remote dispatch and serialize actions across one active task.
- Check cancellation immediately before every dispatch boundary.
- No offline request is automatically executed later.
- Retrieve a pending call using its saved ID where supported; otherwise inspect state and retain uncertainty.
- Reconciliation never restarts the conversation or original mutation automatically.
- Reads/searches/allowlisted launches/media require no repeated approval. New folder/file mutations get a concrete review. Destructive, financial, communication, installation and privileged tools are absent.
- Speech stop and task cancellation are distinct. Partial recognition never enters the execution loop.
- Documents/web/tool output/memories are data, never authority to expand tools, paths, device selection or permissions.
# Gemini setup validation (0.1.1)

- Native Settings uses GeminiValidationController, also exercised by portable
  regression tests. States: noKey, stored, checking, checked, chooseModel, failed.
- Saving/replacing starts a metadata check; deleting cancels and clears its
  catalog. A 25-second independent deadline ends visible progress, and revision
  IDs suppress stale results. Cancellation is a retryable terminal UI outcome.
- Model discovery uses Google's fixed v1beta/models endpoint, x-goog-api-key
  header and bounded pageToken pagination. No key is included in a URL.
- checked means Google accepted the list request and included the selected ID;
  it does not prove generation, billing or quota. A missing model retains the
  returned choices. Only user selection changes the configured model.
- Google HTTP errors keep sanitized fields only; raw bodies and keys are not
  persisted. API key/model/settings changes retain the existing Keychain and
  storage identities across this update.

# ElevenLabs setup and speech (0.1.2)

- Existing display labels normalize to documented model IDs (ElevenV4 becomes
  eleven_v4). Unknown exact API IDs are retained. Voice ID case is never changed.
- Metadata GET /v1/models returns an array; only can_do_text_to_speech models
  enter the native picker. GET /v1/voices/{id} must echo the requested voice_id.
- ElevenValidationController has explicit checking/result/error states, a
  25-second deadline and revision guards. Edits/deletion invalidate stale checks.
- Metadata checks are separate from synthesis. Restricted TTS-only keys may
  explicitly test speech without read access. Validation never incurs a hidden
  synthesis request, and synthesis is never automatically retried.
- POST /v1/text-to-speech/{id}/stream sends JSON text/model_id, xi-api-key in a
  header and output_format=pcm_24000. No credential is included in a URL.
- ElevenLabs error.detail object/string/list forms are bounded and redacted
  before display. HTTP stage/status/reason are retained without raw bodies/keys.


# Native speech playback (0.1.3)

- Cancel capture before output. Use playback/spokenAudio with no explicit A2DP
  option; activate the session before rebuilding the player/mixer graph.
- Provider audio remains signed PCM16 little-endian, 24 kHz mono. Newline bytes
  never delimit audio packets. Convert to Float32 before AVAudioPlayerNode.
- At most eight buffers of at most 1024 frames are queued. Completion waits for
  dataPlayedBack; a stalled queue errors after five seconds. Stop/interruption
  cancels queued work; old requests and callbacks cannot alter a newer playback.
- Device-audio test is local and uses the identical output/decoder/player path.
  It never sends a provider request. Test voice is explicit and may use quota.
- Stage labels separate iPhone session/activation/engine/render failures from
  provider request/stream/decoding errors. Keep provider redaction guarantees.
- CI includes a hosted native iOS Simulator test target. Simulator playback is
  evidence about that runtime, not proof of physical headset or live-key access.

# RDC native registration compatibility (0.1.4)

- A per-install DCR credential may be none, client_secret_post or client_secret_basic
  only when advertised by the trusted server. Reject missing/expired credentials,
  unadvertised methods and a changed callback. PKCE S256/state remain required.
- Never embed a shared secret in source/IPA or reuse another app's token. Runtime
  client credentials go only to trusted HTTPS token/revocation endpoints. Never
  include them in authorization URLs, MCP requests, logs, SQLite or model context.
- Store active discovery/registration/tokens atomically in device-only Keychain;
  cache pending registration separately, migrate legacy public grants, and remove
  all active/pending/legacy records on local credential removal.
- Cancellation/removal invalidates late sign-in/refresh/list/MCP replies. No
  authorization-code, refresh or tool mutation request is automatically retried.
- Device text adapter accepts the observed explicit UUID/status records. Device
  selection and reviewed Windows helper verification are still prerequisites.
