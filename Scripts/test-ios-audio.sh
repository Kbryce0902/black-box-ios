#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/logs
xcrun simctl list devices available --json > build/available-simulators.json
simulator_id="$(python3 - <<'PY'
import json
with open('build/available-simulators.json') as f:
    runtimes = json.load(f)['devices']
phones = [(runtime, d['name'], d['udid']) for runtime, devices in runtimes.items()
          if 'iOS-' in runtime for d in devices if d.get('isAvailable') and d['name'].startswith('iPhone')]
if not phones:
    raise SystemExit('No available iPhone simulator; native audio tests cannot be replaced by core fixtures.')
print(sorted(phones, reverse=True)[0][2])
PY
)"
echo "Running native audio tests on simulator $simulator_id"
simulator_arch="$(uname -m)"
xcodebuild -project BlackBox.xcodeproj -scheme BlackBox -configuration Debug \
  -destination "platform=iOS Simulator,id=$simulator_id,arch=$simulator_arch" -destination-timeout 180 \
  -derivedDataPath build/AudioTestDerivedData -resultBundlePath build/logs/AudioPlayback.xcresult \
  -parallel-testing-enabled NO -only-testing:BlackBoxAudioTests \
  ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual test
