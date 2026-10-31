#!/usr/bin/env bash
set -euo pipefail

if [[ -f android/gradlew ]]; then
  exit 0
fi

manifest_backup="$(mktemp)"
scaffold="$(mktemp -d)"
cleanup() {
  rm -rf -- "$scaffold"
  rm -f -- "$manifest_backup"
}
trap cleanup EXIT

if [[ -f android/app/src/main/AndroidManifest.xml ]]; then
  cp android/app/src/main/AndroidManifest.xml "$manifest_backup"
fi

flutter create \
  --platforms=android \
  --org com.trilok.nabi \
  --project-name nabi_agent \
  "$scaffold"

mkdir -p android
cp -a "$scaffold/android/." android/
if [[ -s "$manifest_backup" ]]; then
  cp "$manifest_backup" android/app/src/main/AndroidManifest.xml
fi
