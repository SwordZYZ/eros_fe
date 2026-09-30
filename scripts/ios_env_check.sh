#!/usr/bin/env bash

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

EXPECTED_XCODE_VERSION="27.0"
EXPECTED_IOS_RUNTIME="iOS 27.0"
EXPECTED_FLUTTER_VERSION="3.47.3"
EXPECTED_COCOAPODS_VERSION="1.16.2"
failures=0

pass() {
  printf 'PASS  %s\n' "$1"
}

fail() {
  printf 'FAIL  %s\n' "$1"
  failures=$((failures + 1))
}

printf 'iOS toolchain baseline for %s\n\n' "$ROOT_DIR"

if command -v xcodebuild >/dev/null 2>&1; then
  xcode_output="$(xcodebuild -version 2>&1)"
  printf '%s\n' "$xcode_output"
  xcode_version="$(printf '%s\n' "$xcode_output" | sed -n 's/^Xcode //p' | head -n 1)"
  if [[ "$xcode_version" == "$EXPECTED_XCODE_VERSION" ]]; then
    pass "Xcode $EXPECTED_XCODE_VERSION"
  else
    fail "Expected Xcode $EXPECTED_XCODE_VERSION; found ${xcode_version:-unavailable}"
  fi
  printf 'Developer directory: %s\n' "$(xcode-select -p 2>&1)"
else
  fail "xcodebuild is unavailable"
fi

if command -v xcrun >/dev/null 2>&1; then
  printf '\nSimulator runtimes:\n'
  runtime_output="$(xcrun simctl list runtimes 2>&1)"
  printf '%s\n' "$runtime_output"
  if printf '%s\n' "$runtime_output" | grep -Fq "$EXPECTED_IOS_RUNTIME ("; then
    pass "$EXPECTED_IOS_RUNTIME runtime is installed"
  else
    fail "$EXPECTED_IOS_RUNTIME runtime is not installed"
  fi

  printf '\nAvailable simulator devices:\n'
  device_output="$(xcrun simctl list devices available 2>&1)"
  printf '%s\n' "$device_output"
  if printf '%s\n' "$device_output" | grep -Fq "$EXPECTED_IOS_RUNTIME"; then
    pass "Available devices are listed for $EXPECTED_IOS_RUNTIME"
  else
    fail "No available simulator devices were listed for $EXPECTED_IOS_RUNTIME"
  fi

  printf '\nPhysical Apple devices known to Xcode:\n'
  if xcrun devicectl list devices 2>&1; then
    :
  else
    printf 'devicectl could not list physical devices on this host.\n'
  fi
  printf '\nlipo tool: '
  xcrun --find lipo 2>&1 || fail "Xcode lipo tool is unavailable"
else
  fail "xcrun is unavailable"
fi

flutter_command=()
if [[ -n "${IOS_FLUTTER_BIN:-}" ]]; then
  flutter_command=("$IOS_FLUTTER_BIN")
elif command -v fvm >/dev/null 2>&1; then
  flutter_command=(fvm flutter)
elif [[ -x "$ROOT_DIR/.fvm/flutter_sdk/bin/flutter" ]]; then
  flutter_command=("$ROOT_DIR/.fvm/flutter_sdk/bin/flutter")
elif command -v flutter >/dev/null 2>&1; then
  flutter_command=(flutter)
fi

if [[ ${#flutter_command[@]} -gt 0 ]]; then
  printf '\nFlutter SDK:\n'
  flutter_output="$("${flutter_command[@]}" --version 2>&1)"
  flutter_status=$?
  printf '%s\n' "$flutter_output"
  flutter_version="$(printf '%s\n' "$flutter_output" | sed -n 's/^Flutter \([^ ]*\).*/\1/p' | head -n 1)"
  if [[ $flutter_status -eq 0 && "$flutter_version" == "$EXPECTED_FLUTTER_VERSION" ]]; then
    pass "Flutter $EXPECTED_FLUTTER_VERSION"
    printf '\nFlutter visible devices:\n'
    "${flutter_command[@]}" devices 2>&1 || fail "Flutter could not enumerate devices"
  else
    fail "Expected Flutter $EXPECTED_FLUTTER_VERSION; found ${flutter_version:-unavailable}"
  fi
else
  fail "Flutter or FVM is unavailable; install the version pinned in .fvmrc"
fi

printf '\nDependency manager versions and lockfiles:\n'
if command -v ruby >/dev/null 2>&1; then
  ruby --version
else
  fail "Ruby is unavailable"
fi
if command -v bundle >/dev/null 2>&1; then
  bundle --version
  if bundle check; then
    pass "Ruby gems from Gemfile.lock are installed"
  else
    fail "Ruby gems from Gemfile.lock are missing; run bundle install"
  fi
  pod_version="$(bundle exec pod --version 2>&1)"
  pod_status=$?
  printf 'Bundled CocoaPods: %s\n' "$pod_version"
  lock_pod_version="$(sed -n 's/^COCOAPODS: //p' ios/Podfile.lock | head -n 1)"
  if [[ $pod_status -eq 0 && "$pod_version" == "$EXPECTED_COCOAPODS_VERSION" && "$lock_pod_version" == "$EXPECTED_COCOAPODS_VERSION" ]]; then
    pass "CocoaPods $EXPECTED_COCOAPODS_VERSION matches ios/Podfile.lock"
  else
    fail "Expected bundled CocoaPods and ios/Podfile.lock at $EXPECTED_COCOAPODS_VERSION (lockfile: ${lock_pod_version:-missing})"
  fi
else
  fail "Bundler is unavailable; install the Ruby dependencies from Gemfile.lock"
fi

if [[ -f pubspec.lock ]]; then
  pass "pubspec.lock exists"
  if grep -Eq '^[[:space:]]+enable-swift-package-manager: false$' pubspec.yaml; then
    pass "Swift Package Manager is disabled in pubspec.yaml"
  else
    fail "pubspec.yaml must disable Swift Package Manager for the CocoaPods baseline"
  fi
  if [[ ${#flutter_command[@]} -gt 0 ]] && "${flutter_command[@]}" pub deps --style=compact >/dev/null 2>&1; then
    pass "Flutter dependency graph resolves from pubspec.lock"
  else
    fail "Flutter dependencies do not resolve from pubspec.lock"
  fi
else
  fail "pubspec.lock is missing"
fi

printf '\niOS deployment target:\n'
podfile_target="$(sed -n "s/^\$iOSVersion = '\([^']*\)'/\1/p" ios/Podfile | head -n 1)"
if [[ "$podfile_target" == "15.6" ]] && grep -Fq 'IPHONEOS_DEPLOYMENT_TARGET = 15.6;' ios/Runner.xcodeproj/project.pbxproj; then
  pass "Podfile and Runner target agree on iOS 15.6"
else
  fail "Podfile target (${podfile_target:-missing}) must match Runner's iOS 15.6 target"
fi

printf '\n'
if [[ $failures -eq 0 ]]; then
  printf 'iOS toolchain baseline is ready.\n'
else
  printf 'iOS toolchain baseline has %s failure(s).\n' "$failures"
  exit 1
fi
