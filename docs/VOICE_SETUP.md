# Authorized Black_Box voice setup

The app consumes an ElevenLabs voice ID; it does not create or verify a clone automatically. The target remains the authorized James Spader/Ultron voice. No supplied recording or authorized account voice ID was available during implementation, so no target voice has been created or evaluated.

ElevenLabs supports Instant Voice Cloning from samples and Professional Voice Cloning with a dedicated verification process. Its published PVC route requires the voice owner to create and verify the voice on their own account, then share it privately using a supported sharing link. Accept the shared voice in the account whose API key Black_Box will use and enter that accessible ID in Settings. Permission for the material does not invent an API capability to bypass the provider's verification process.

For an authorized Instant Voice Clone, use ElevenLabs' current creation interface/API and complete whatever verification it requires for that account and material. Do not assume the app can create the precise performance from text alone. No clone creation, subscription change or paid setup was performed here.

In Black_Box:

1. Store your own ElevenLabs key in Settings. The input clears after storage; the key is retained in Keychain only.
2. Enter the accessible voice ID and a supported text-to-speech model ID. The default is `eleven_flash_v2_5`, configurable without a source change.
3. Use Validate voice access, then explicitly start the short playback test, which uses provider quota.
4. Listen over the phone speaker and your Bluetooth/headset route. Evaluate the exact voice, pronunciation and delivery before relying on it.

The text persona is concise, confident and dry. Vocal identity comes from the selected authorized ElevenLabs voice, not a claim that the text prompt reproduces an actor's timbre.

Official sources checked 2026-11-01:
- https://elevenlabs.io/docs/eleven-creative/voices/voice-cloning
- https://elevenlabs.io/docs/help-center/product/voices/voice-cloning/can-i-create-a-professional-voice-clone-of-someone-elses-voice
- https://elevenlabs.io/docs/help-center/product/voices/my-voices/how-do-i-share-a-voice
- https://elevenlabs.io/docs/api-reference/text-to-speech/stream
