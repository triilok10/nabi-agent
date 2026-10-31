#!/usr/bin/env bash
set -euo pipefail

cd /workspace
bash scripts/ensure-android-scaffold.sh
flutter pub get
flutter analyze
flutter test
flutter build apk --release
