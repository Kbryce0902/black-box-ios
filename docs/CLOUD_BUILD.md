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
run 41337372895 at source commit 5daf301fee080a8c0b491a2eca12cf6e45cb34ee. No Gemini, ElevenLabs or RDC credentials are uploaded.

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
4. Check the native audio step: `Scripts/test-ios-audio.sh` runs 11 hosted iOS
   Simulator regressions (nine audio and two real Keychain tests) with local PCM and no provider key. Inspect the actual
   test results; compilation alone does not establish playback.
5. Download the **BlackBox-SideStore** artifact and extract it. The contained
   `BlackBox-0.1.5-unsigned.ipa` is a device build awaiting SideStore re-signing.
   The adjacent SHA-256 checksum identifies those exact bytes.
6. Import the IPA into SideStore on the phone using the user's existing Apple
   Account setup. Record installation and launch results before calling it a
   verified installable release.

The package verifier checks ZIP integrity, bundle metadata, executable permission,
arm64 Mach-O structure and the physical iOS platform in both the plist and binary.
The script publishes a new local IPA only after the actual Xcode build and these
checks succeed. It cannot prove signing, installation or live provider operation.

RDC registration compatibility is implemented in 0.1.4; the owner now reports native browser sign-in and device listing work.
0.1.5 desktop command readiness is compiled and tested; actual native PC
commands still require phone acceptance.
The simulator host uses local ad-hoc signing for Keychain tests. The device
IPA packaging step remains unsigned and needs SideStore re-signing.

Official references:
- https://docs.github.com/en/actions/concepts/billing-and-usage
- https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md
- https://docs.sidestore.io/docs/installation/install

## Retrieved artifact

The successful native build and all 94 Mac core and 11 native iOS tests passed. The downloaded
`BlackBox-0.1.5-unsigned.ipa` is 940422 bytes; SHA-256:

`92f951540b4046985291b5f11806ab6f71d9b67e1866d15ebe273643c1490fe9`

It targets arm64 iPhoneOS, minimum iOS 17.0. SideStore re-signing and actual phone
installation/launch remain pending. The owner reports native RDC sign-in on 0.1.4; native 0.1.5 PC command acceptance remains pending.
