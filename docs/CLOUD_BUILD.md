# Compile an IPA without a local Mac

The prepared GitHub Actions workflow builds the native iOS project on a standard
`macos-15` runner with Xcode 26.3, an installed toolchain listed in the official
runner image on 2026-11-01. It does not require an Apple signing certificate or
Gemini, ElevenLabs or RDC credentials. Provider credentials are entered on the
phone after installation.

## Authorization and current state

The owner explicitly authorized creating a public repository on 2026-11-01.
https://github.com/Kbryce0902/black-box-ios was created and independently confirmed
as public with write access through the GitHub connection. The existing
AetherMedia repository is unrelated and must not be reused.

The destination is the dedicated **public `Kbryce0902/black-box-ios` repository**
containing only this BlackBox source tree. The source upload and native compilation succeeded in
run 41297291686 at source commit 93af30d7d00bf4abc4c6eb959ca92ec64494b636. No Gemini, ElevenLabs or RDC credentials are uploaded.

The workflow refuses private-repository Mac jobs before allocating a runner,
because private usage can exceed an included allowance and incur charges.
Standard hosted compute for public repositories is free under GitHub's current
policy. Artifact retention is limited to one day; no paid service is enabled.

## Reproduce the verified build

1. Upload the **contents of `BlackBox/` at repository root**. Do not upload the
   enclosing source ZIP, `.build/`, temporary files, provider credentials,
   verification-attempt logs or unrelated projects.
2. Preserve `.github/workflows/build-ios.yml`. An approved push to `main` starts
   the build; it can also be started with **Actions → Build Black_Box for
   SideStore → Run workflow**.
3. Check the actual `core-tests` and `device-build` logs. Fix real Apple compiler
   errors and repeat until the run succeeds. Local Linux checks do not substitute
   for this compilation.
4. Download the **BlackBox-SideStore** artifact and extract it. The contained
   `BlackBox-0.1.2-unsigned.ipa` is a device build awaiting SideStore re-signing.
   The adjacent SHA-256 checksum identifies those exact bytes.
5. Import the IPA into SideStore on the phone using the user's existing Apple
   Account setup. Record installation and launch results before calling it a
   verified installable release.

The package verifier checks ZIP integrity, bundle metadata, executable permission,
arm64 Mach-O structure and the physical iOS platform in both the plist and binary.
The script publishes a new local IPA only after the actual Xcode build and these
checks succeed. It cannot prove signing, installation or live provider operation.

RDC's native public-client authentication issue remains independent of compiling
the app. Conversation and provider setup may be tested while that gate is closed.

Official references:
- https://docs.github.com/en/actions/concepts/billing-and-usage
- https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md
- https://docs.sidestore.io/docs/installation/install

## Retrieved artifact

The successful native build and all 64 Mac tests passed. The downloaded
`BlackBox-0.1.2-unsigned.ipa` is 852941 bytes; SHA-256:

`e0a78a247b734ea59cd6b785b72a202e468a35cbe2d50cb87e1a743c709858cb`

It targets arm64 iPhoneOS, minimum iOS 17.0. SideStore re-signing and actual phone
installation/launch remain pending. The RDC native-client gate is unchanged.
