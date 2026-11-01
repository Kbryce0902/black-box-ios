# Build, phone and PC setup

## Prerequisites

- A Mac with Xcode and a suitable installed iOS SDK for compilation. The verified CI build used Xcode 26.3 (17C529), Apple Swift 6.2.4 and the iOS 26.2 SDK on macOS 15.8.2. Actual phone installation/launch is still pending. Check Apple's support table for direct Xcode device debugging on the actual phone OS; this Linux workspace uses the GitHub Mac runner for compilation.
- Your own Gemini API key from Google AI Studio. Choose a model actually available to that key; the starting ID is configurable.
- Your own ElevenLabs API key, access to the desired authorized voice ID and a supported TTS model.
- A **public native RDC client registration** for `com.kellen.blackbox:/oauth/callback`, with PKCE S256 and no client secret. See FEASIBILITY.md: the tested dynamic path returned a confidential registration and is rejected.
- A paired Windows PC with the RDC remote agent awake and online. RDC's published minimum is Node.js 18+. This is a minimum, not a recommendation to install an obsolete runtime. Verify the current Node installer supports the actual Windows 10 x64 build before installation. No Node installation or PC inspection occurred in this build session.

Enter provider keys in the app, not a source/configuration file. No account key is required for the portable tests.

## Mac checks and build

For a Mac runner hosted by GitHub instead of a local Mac, see
[CLOUD_BUILD.md](CLOUD_BUILD.md). The workflow, remote compilation and packaging checks have passed;
SideStore re-signing and phone installation remain pending.

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

Only after `xcodebuild` successfully produces a real `iphoneos` app does the script package `build/BlackBox-0.1.0-unsigned.ipa`. It is unsigned and must be re-signed; it is not an App Store archive or a claim of successful installation. The script exits explicitly on Linux and never fabricates an IPA.

For a direct Xcode install, choose your signing team and a bundle ID provisioned for that account. No development team, signing certificate or provisioning profile is supplied. Keep the callback URL scheme `com.kellen.blackbox` registered even if re-signing changes the app bundle identifier.

## SideStore

Use the current official guide: https://docs.sidestore.io/docs/installation/install

The documented process includes USB trust/pairing on initial setup, Apple Account signing, enabling Developer Mode where required, LocalDevVPN and refreshing SideStore. Follow its current OS-specific instructions. Import the successfully built unsigned IPA through SideStore's app installation workflow and let SideStore re-sign it. Verify microphone/Speech permission prompts and the OAuth callback afterward. This project uses no JIT, background-audio keepalive or special distribution entitlement. The real arm64 IPA is built, but compatibility on the user's actual iPhone and iOS build has not been tested.

If SideStore changes the bundle identifier, verify independent Keychain storage and callback behavior after every installation/update; the source's callback scheme is explicit and not generated from the re-signed identifier.

## App provider setup

1. Open Settings. Store the Gemini and ElevenLabs keys separately. After storage the input clears and only a masked presence indicator is shown. Validate the Gemini key/model and ElevenLabs voice access.
2. Save the configured model, voice ID and limits. Explicitly run the short inference and playback harness tests; these consume your provider quota. No paid service is enabled by the app.
3. Check RDC discovery. Supply only a provider-issued **public** client ID if dynamic registration still returns a secret. Start Sign in with PKCE. Complete the system browser consent/callback flow. Never paste a token from ChatGPT or another application.
4. Refresh paired devices and select the intended computer explicitly. No automatic first-device selection occurs.
5. Add aliases such as projects, school and downloads with actual absolute Windows paths for that device. Search/read/open paths are restricted to these roots.
6. Install the reviewed helper on the PC as below, enter its absolute path, and check the helper handshake. It expires after app backgrounding/device changes.

## Windows agent and helper

RDC's official command is:

```powershell
node --version
npx @wonderwhy-er/desktop-commander@latest remote
```

First use downloads the provider's package and opens device pairing. Confirm the displayed pairing codes match, then keep the terminal open. Closing it or sleeping the PC ends access. The included `Desktop/Start-BlackBox-RDC.cmd` runs that command in the user's session; it does not install a service or elevate privileges. Nothing was installed during this development session.

For predictable updates, after first successful acceptance record the actual tested package/runtime versions and pin the package version in your local launcher. No untested version has been presented as a validated Windows 10 runtime.

Copy the reviewed `Desktop/BlackBoxHelper.ps1` to a user-owned folder, for example under Documents/Black_Box. Inspect the script, then if Windows marks the downloaded copy as blocked, unblock that specific reviewed file. The helper invokes PowerShell with process-scoped RemoteSigned; it does not change the machine's global execution policy, and domain policy can still block it. An enforced block is a setup error, not grounds to run as administrator.

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
- DCR returns client_secret_post: native gate remains blocked. Obtain a supported public registration; do not embed that secret.
- Unknown device output/schema: keep the gate closed and update the versioned adapter using real, redacted native results.
- Helper handshake missing: check actual path, script review/unblock, Windows/PowerShell and RDC output. A started process is not a successful helper result.
- Unknown task/action: retrieve the existing remote call if an ID exists or inspect actual PC state. Do not press repeated launch/mutation requests to probe for success.
- iOS suspension: foreground the app, inspect Activity, refresh devices and re-check the helper. Stale queued actions are not resumed.
