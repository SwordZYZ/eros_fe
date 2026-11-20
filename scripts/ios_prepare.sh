#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/scripts/ios_common.sh"
ios_require_project_lock "$ROOT_DIR/scripts/ios_prepare.sh" "$@"
cd "$ROOT_DIR"

EXPECTED_FLUTTER_VERSION="3.47.3"
LOCAL_CONFIG="ios/Flutter/Local.xcconfig"
LOCAL_CONFIG_EXAMPLE="ios/Flutter/Local.xcconfig.example"

die() {
  printf 'iOS preparation failed: %s\n' "$1" >&2
  exit 1
}

usage() {
  printf 'Usage: %s [--simulator|--device]\n' "$0" >&2
  exit 2
}

if [[ $# -gt 1 ]]; then
  usage
fi

mode="--simulator"
if [[ $# -eq 1 ]]; then
  mode="$1"
fi
case "$mode" in
  --simulator|--device) ;;
  *) usage ;;
esac

if [[ ! -f "$LOCAL_CONFIG" ]]; then
  cp "$LOCAL_CONFIG_EXAMPLE" "$LOCAL_CONFIG"
  printf 'Created %s from the checked-in example.\n' "$LOCAL_CONFIG"
fi

if ! git check-ignore -q "$LOCAL_CONFIG"; then
  die "$LOCAL_CONFIG must remain a local-only ignored file"
fi

xcconfig_value() {
  awk -F= -v key="$1" '$1 ~ "^[[:space:]]*" key "[[:space:]]*$" {value=substr($0, index($0, "=") + 1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)} END {print value}' "$LOCAL_CONFIG" | tr -d '[:space:]'
}

bundle_identifier="$(xcconfig_value IOS_DEVELOPMENT_BUNDLE_IDENTIFIER)"
team_id="$(xcconfig_value IOS_DEVELOPMENT_TEAM)"

if [[ ! "$bundle_identifier" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]]; then
  die "Set a valid IOS_DEVELOPMENT_BUNDLE_IDENTIFIER in $LOCAL_CONFIG"
fi

if [[ "$mode" == "--device" ]]; then
  if [[ "$bundle_identifier" == "com.example.erosfe.dev" ]]; then
    die "Set a bundle identifier registered to your Apple Developer team in $LOCAL_CONFIG before a device build"
  fi
  if [[ ! "$team_id" =~ ^[A-Z0-9]{10}$ ]]; then
    die "Set your 10-character IOS_DEVELOPMENT_TEAM in $LOCAL_CONFIG before a device build"
  fi
elif [[ -n "$team_id" && ! "$team_id" =~ ^[A-Z0-9]{10}$ ]]; then
  die "IOS_DEVELOPMENT_TEAM in $LOCAL_CONFIG must be empty or a 10-character team ID"
fi

if [[ ! -s lib/config/config.dart ]] \
  || ! grep -Fq 'class FeConfig {' lib/config/config.dart \
  || ! grep -Eq 'static const openLapikey[[:space:]]*=' lib/config/config.dart \
  || ! grep -Eq 'static const sentryDsn[[:space:]]*=' lib/config/config.dart; then
  die "lib/config/config.dart is missing or does not define the required FeConfig values"
fi

resources_phase="$(sed -n '/Begin PBXResourcesBuildPhase section/,/End PBXResourcesBuildPhase section/p' \
  ios/Runner.xcodeproj/project.pbxproj)"
if [[ "$resources_phase" == *GoogleService-Info.plist* ]]; then
  die "The encrypted Firebase plist must not be included in Runner resources while Firebase is disabled"
fi

if ! plutil -lint ios/Runner/Info.plist ios/Runner/fehviewer.entitlements >/dev/null; then
  die "An active iOS Info.plist or entitlements file is invalid"
fi

expected_xcode_version="$(ios_expected_xcode_version)" || die "Could not read the pinned Xcode version"
xcode_output="$(xcodebuild -version 2>&1)" || die "xcodebuild is unavailable"
xcode_version="$(printf '%s\n' "$xcode_output" | sed -n 's/^Xcode //p' | head -n 1)"
if [[ "$xcode_version" != "$expected_xcode_version" ]]; then
  die "Expected Xcode $expected_xcode_version; found ${xcode_version:-unavailable}"
fi

ios_select_flutter "$EXPECTED_FLUTTER_VERSION" || die "Could not select the pinned Flutter SDK"
flutter_version="$EXPECTED_FLUTTER_VERSION"
flutter_sdk_root="$("${flutter_command[@]}" --version --machine 2>/dev/null \
  | python3 -c 'import json, sys; print(json.load(sys.stdin)["flutterRoot"])')" \
  || die "Could not locate the Dart SDK bundled with Flutter"
dart_command=("$flutter_sdk_root/bin/cache/dart-sdk/bin/dart")
if [[ ! -x "${dart_command[0]}" ]]; then
  die "The pinned Flutter SDK does not contain its Dart executable"
fi

printf 'Preparing iOS %s configuration with Flutter %s and Xcode %s.\n' \
  "${mode#--}" "$flutter_version" "$xcode_version"
printf 'Bundle identifier: %s\n' "$bundle_identifier"
if [[ "$mode" == "--device" ]]; then
  printf 'Development team: %s\n' "$team_id"
else
  printf 'Development signing team is optional for unsigned Simulator builds.\n'
fi

if ! command -v bundle >/dev/null 2>&1; then
  die "Bundler is unavailable; install Ruby Bundler before preparing CocoaPods"
fi
if ! bundle check >/dev/null 2>&1; then
  bundle install --jobs 4 --retry 3
fi

flutter_pub_get_side_effects=(
  analysis_options.yaml
  macos/Flutter/GeneratedPluginRegistrant.swift
  windows/flutter/generated_plugin_registrant.cc
  windows/flutter/generated_plugins.cmake
)
flutter_pub_get_snapshot="$(mktemp -d)"
restore_flutter_pub_get_side_effects() {
  local path
  for path in "${flutter_pub_get_side_effects[@]}"; do
    if [[ -f "$flutter_pub_get_snapshot/$path" ]]; then
      cp -p "$flutter_pub_get_snapshot/$path" "$path"
    fi
  done
  rm -rf "$flutter_pub_get_snapshot"
}
for path in "${flutter_pub_get_side_effects[@]}"; do
  if [[ -f "$path" ]]; then
    mkdir -p "$flutter_pub_get_snapshot/$(dirname "$path")"
    cp -p "$path" "$flutter_pub_get_snapshot/$path"
  fi
done
trap restore_flutter_pub_get_side_effects EXIT

"${flutter_command[@]}" pub get --enforce-lockfile
"${flutter_command[@]}" analyze lib/config/config.dart
restore_flutter_pub_get_side_effects
trap - EXIT
"${dart_command[@]}" run build_runner build --delete-conflicting-outputs --fail-on-severe
"${dart_command[@]}" run intl_utils:generate

(
  cd ios
  bundle exec pod install --deployment
)

printf '\niOS preparation complete. You can now build an unsigned iOS Debug app.\n'
printf '  scripts/ios_dev.sh build ios --debug --no-codesign\n'
