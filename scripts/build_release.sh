#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
flutter_bin="${SCHULPILOT_FLUTTER:-$HOME/.local/share/schulpilot-flutter/bin/flutter}"
export SCHULPILOT_SIGNING_PROPERTIES="${SCHULPILOT_SIGNING_PROPERTIES:-$HOME/.local/share/schulpilot-signing/signing.properties}"
export SCHULPILOT_STORE_BUILD=true
test -f "$SCHULPILOT_SIGNING_PROPERTIES"
"$flutter_bin" --version --machine | python3 -c 'import json,sys; expected=json.load(open("toolchain.json")); actual=json.load(sys.stdin); assert actual["frameworkRevision"]==expected["flutter_revision"] and actual["dartSdkVersion"].split()[0]==expected["dart"], "Use the pinned Flutter SDK"'
cd app
"$flutter_bin" pub get --enforce-lockfile
"$flutter_bin" build web --release --no-pub --no-web-resources-cdn --csp
"$flutter_bin" build apk --flavor direct --release --dart-define=API_URL=https://schulpilot.dorfspy.de/api --no-pub
"$flutter_bin" build appbundle --flavor play --release --dart-define=API_URL=https://schulpilot.dorfspy.de/api --no-pub
cp build/app/outputs/flutter-apk/app-direct-release.apk ../artifacts/schulpilot-android.apk
cp build/app/outputs/bundle/playRelease/app-play-release.aab ../artifacts/schulpilot-play.aab
chmod 600 ../artifacts/schulpilot-android.apk ../artifacts/schulpilot-play.aab
cd ..
python3 scripts/android_manifest.py
