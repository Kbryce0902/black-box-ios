# Build, phone and PC setup

## Prerequisites

- A Mac with Xcode and a suitable installed iOS SDK for compilation. The verified CI build used Xcode 26.3 (17C529), Apple Swift 6.2.4 and the iOS 26.2 SDK on macOS 15.8.2. The owner reports 0.1.4 installs and signs in to RDC; 0.1.5 command acceptance is pending. Check Apple's support table for direct Xcode device debugging on the actual phone OS; this Linux workspace uses the GitHub Mac runner for compilation.
- Your own Gemini API key from Google AI Studio. Choose a model actually available to that key; the starting ID is configurable.
- Your own ElevenLabs API key, access to the desired authorized voice ID and a supported TTS model.
- An RDC account paired to your PC. In 0.1.4, Black_Box registers each installation automatically, stores its runtime credential in Keychain and uses browser sign-in with PKCE. Leave the optional public client ID blank for normal setup; no shared credential is supplied in the app.
- A paired Windows PC with the RDC remote agent awake and online. RDC's published minimum is Node.js 18+. This is a minimum, not a recommendation to install an obsolete runtime. Verify the current Node installer supports the actual Windows 10 x64 build before installation. The helper has been checked on Windows 10 / PowerShell 5.1 through the separate RDC connector; no Node installation was performed.

Enter provider keys in the app, not a source/configuration file. No account key is required for the portable tests.

## Mac checks and build

For a Mac runner hosted by GitHub instead of a local Mac, see
[CLOUD_BUILD.md](CLOUD_BUILD.md). The workflow, remote compilation and packaging checks have passed;
The owner reports successful SideStore installation and RDC login on 0.1.4. The 0.1.5 update still needs phone command acceptance.

From the extracted BlackBox directory:

```sh
xcodebuild -version
xcodebuild -showsdks
swift test --jobs 1
Scripts/build-ios.sh simulator
```

The checked-in Xcode project references the local BlackBoxCore package. SQLite and all iOS frameworks are system dependencies. No CocoaPods, XcodeGen or external Swift package is required. Select a compatible installed simulator in Xcode for an actual run; a generic simulator build is compilation only. Microphone/recognition and Bluetooth tests require a real phone.

To build an unsigned device artifact for SideStore:

```sh
Scripts/build-ios.sh unsigned
```

Only after `xcodebuild` successfully produces a real `iphoneos` app does the script package `build/BlackBox-0.1.5-unsigned.ipa`. It is unsigned and must be re-signed; it is not an App Store archive or a claim of successful installation. The script exits explicitly on Linux and never fabricates an IPA.

For a direct Xcode install, choose your signing team and a bundle ID provisioned for that account. No development team, signing certificate or provisioning profile is supplied. Keep the callback URL scheme `com.kellen.blackbox` registered even if re-signing changes the app bundle identifier.

## SideStore

Use the current official guide: https://docs.sidestore.io/docs/installation/install

The documented process includes USB trust/pairing on initial setup, Apple Account signing, enabling Developer Mode where required, LocalDevVPN and refreshing SideStore. Follow its current OS-specific instructions. Import the successfully built unsigned IPA through SideStore's app installation workflow and let SideStore re-sign it. Verify microphone/Speech permission prompts and the OAuth callback afterward. This project uses no JIT, background-audio keepalive or special distribution entitlement. The real arm64 IPA is built, but compatibility on the user's actual iPhone and iOS build has not been tested.

If SideStore changes the bundle identifier, verify independent Keychain storage and callback behavior after every installation/update; the source's callback scheme is explicit and not generated from the re-signed identifier.

## App provider setup

0.1.3 fixes iPhone playback setup and binary PCM buffering. After updating,
use **Test device audio (no API usage)** first; the local tone exercises the same
session/decoder/player as speech. Settings shows the selected **Output** route.
Then use **Test voice (uses API quota)** to exercise actual ElevenLabs synthesis.
Errors identify whether native setup/activation/engine, provider request/stream,
audio decoding or rendering failed. Stop/interruption cancels old playback; no
speech request is silently retried. Keep the phone's media volume audible and
check the displayed route if a connected headset receives the audio.

0.1.2 changes ElevenLabs setup: voice/model edits autosave; known display labels
normalize to exact IDs (ElevenV4 becomes eleven_v4). Use Check voice and model to
load the returned TTS model choices and verify the Voice ID. The native check has
a 25-second deadline and shows the provider's redacted reason on failure.
Test voice (uses API quota) explicitly calls synthesis and displays the actual
playback/request result beside setup. A key with Text to Speech access can use
that test even if metadata read access is restricted. Grant only the endpoint
permissions you intend to use; no permissions are changed by this app.

Before updating from an earlier version, use Save configuration to preserve any
voice/model entries still only on screen. Install over the same app through
SideStore; 0.1.3 keeps the same bundle, Keychain and SQLite identities.


0.1.1 changes Gemini setup: **Save and check key** stores it securely and starts
a metadata-only check. A progress indicator ends with a result or a visible
error within 25 seconds. An already stored key is checked when Settings opens.
Use **Check connection** to retry, or **Cancel connection check** to stop it.
If the configured model is not returned, choose an ID from **Google models**.
Google's model listing is separate from actual inference and available quota;
send a message or explicitly run the response harness to test that next.


1. Open Settings. Store the Gemini and ElevenLabs keys separately. After storage the input clears and only a masked presence indicator is shown. Validate the Gemini key/model and ElevenLabs voice access.
2. Save the configured model, voice ID and limits. Explicitly run the short inference and playback harness tests; these consume your provider quota. No paid service is enabled by the app.
3. Under Independent RDC sign-in, leave the optional client ID blank and tap Sign in with PKCE. Complete the browser sign-in with the same RDC account used for your PC. The app handles its own per-install registration and callback. Progress, cancel and redacted errors are shown inline; no token copying is required.
4. Refresh paired devices and select the intended computer explicitly. No automatic first-device selection occurs.
5. Add aliases such as projects, school and downloads with actual absolute Windows paths for that device. Search/read/open paths are restricted to these roots.
6. Install the reviewed helper on the PC as below. Leave the helper path blank for the standard installation, then use Find and check helper. In 0.1.5, the app automatically checks on PC selection, foregrounding and before a request when readiness is missing. PC ready means the capability check passed; each command must still return its own result.

## Windows agent and helper

RDC's official command is:

```powershell
node --version
npx @wonderwhy-er/desktop-commander@latest remote
```

First use downloads the provider's package and opens device pairing. Confirm the displayed pairing codes match, then keep the terminal open. Closing it or sleeping the PC ends access. The included `Desktop/Start-BlackBox-RDC.cmd` runs that command in the user's session; it does not install a service or elevate privileges. The current helper was copied and checked in a user-owned LocalAppData folder through the separate connector. No service, startup item, agent or machine policy was installed or changed.

For predictable updates, after first successful acceptance record the actual tested package/runtime versions and pin the package version in your local launcher. No untested version has been presented as a validated Windows 10 runtime.

For the standard installation, create `$env:LOCALAPPDATA\BlackBox-iOS` and copy
the reviewed `Desktop/BlackBoxHelper.ps1` into it. Leave the app's helper path
blank to discover this folder. For a different location, enter that script's
full absolute Windows path in Settings. Inspect the script, then if Windows
marks the downloaded copy as blocked, unblock that specific reviewed file. The helper invokes PowerShell with process-scoped RemoteSigned; it does not change the machine's global execution policy, and domain policy can still block it. An enforced block is a setup error, not grounds to run as administrator.

Run the focused acceptance checks on the actual Windows PC:

```powershell
powershell.exe -NoProfile -ExecutionPolicy RemoteSigned -File .\Desktop\Test-BlackBoxHelper.ps1
```

This creates and removes a dedicated temporary test directory. It tests no-overwrite folder/file operations, path rejection and measured resource output. With `-IncludeLaunchAndMedia` it also sends the YouTube/Notepad/media actions; use that switch only when ready to visually verify those effects. A launch acknowledgement alone is not proof of browser or playback state.

To start RDC at normal user logon, first prove manual pairing/launch. Then create a shortcut to your reviewed launcher in the per-user Startup folder (`shell:startup`), without Run as administrator. This is an optional manual setup step; no startup item was created here. Keep the PC awake only when remote access is wanted. Startup does not make a powered-off or sleeping machine reachable.

## Revoke and remove access

The app uses a discovered OAuth revocation endpoint if one is advertised. The checked metadata did not expose one. Use the provider's dashboard and supported account/grant controls; do not confuse revoking a paired PC with revoking a particular OAuth client grant. Ask RDC for the supported grant-revocation route if none is exposed. The separately labeled Remove local credentials button deletes only this app's Keychain credentials.

## Troubleshooting

- Chat/research can work with PC offline; they still require internet, a valid Gemini key and provider quota.
- 0.1.3 registration/architecture error: update to 0.1.4, which handles supported per-install DCR credentials. Leave the optional client ID blank. The phone must still complete its own browser grant. For a stale/expired registration, Remove local RDC credentials and sign in again; that does not revoke server access.
- Unknown device output/schema: keep the gate closed and update the versioned adapter using real, redacted native results.
- PC online but Gemini says no execution tools: update to 0.1.5, select the intended PC in Computer, and use Find and check helper. Wait for PC ready, then send a fresh request such as "Measure my current RAM usage." The old answer may remain in history, but current capabilities override it.
- Helper check fails: inspect the inline reason, actual path, script review/unblock and RDC output. The default lookup is LocalAppData/BlackBox-iOS/BlackBoxHelper.ps1. A started process is not a successful helper result.
- RDC MCP is separate from Microsoft Remote Desktop/RDP; opening port 3389 is not part of connecting this app. The app exposes fixed URL/app, media, resource and reviewed folder/file operations, not unrestricted shell commands or general desktop clicking.
- Unknown task/action: retrieve the existing remote call if an ID exists or inspect actual PC state. Do not press repeated launch/mutation requests to probe for success.
- iOS suspension: foreground the app and inspect Activity. The helper check restarts automatically; interrupted commands are never replayed. Use Find and check helper if the inline check fails.
