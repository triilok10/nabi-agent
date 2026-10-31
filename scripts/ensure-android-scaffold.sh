#!/usr/bin/env bash
set -euo pipefail

if [[ -f android/gradlew ]]; then
  exit 0
fi

manifest_backup="$(mktemp)"
main_activity_backup="$(mktemp)"
scaffold="$(mktemp -d)"
cleanup() {
  rm -rf -- "$scaffold"
  rm -f -- "$manifest_backup"
  rm -f -- "$main_activity_backup"
}
trap cleanup EXIT

if [[ -f android/app/src/main/AndroidManifest.xml ]]; then
  cp android/app/src/main/AndroidManifest.xml "$manifest_backup"
fi
if [[ -f android/app/src/main/kotlin/com/trilok/nabi/nabi_agent/MainActivity.kt ]]; then
  cp android/app/src/main/kotlin/com/trilok/nabi/nabi_agent/MainActivity.kt "$main_activity_backup"
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
if [[ -s "$main_activity_backup" ]]; then
  mkdir -p android/app/src/main/kotlin/com/trilok/nabi/nabi_agent
  cp "$main_activity_backup" android/app/src/main/kotlin/com/trilok/nabi/nabi_agent/MainActivity.kt
fi

if [[ -f android/app/build.gradle.kts ]]; then
  sed -i 's/minSdk = flutter\.minSdkVersion/minSdk = 24/' android/app/build.gradle.kts
elif [[ -f android/app/build.gradle ]]; then
  sed -i 's/minSdkVersion flutter\.minSdkVersion/minSdkVersion 24/' android/app/build.gradle
fi
