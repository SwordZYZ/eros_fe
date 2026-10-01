#!/usr/bin/env bash

# Shared by iOS preparation, development and the existing IPA scripts.
IOS_ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

ios_require_project_lock() {
  local entrypoint="$1"
  shift
  case "${IOS_LOCK_WAIT:-1}" in
    1) ;;
    0) ;;
    *) printf 'IOS_LOCK_WAIT must be 0 or 1.\n' >&2; exit 2 ;;
  esac
  if python3 "$IOS_ROOT_DIR/scripts/ios_lock.py" --check; then
    return
  fi
  # Re-execute before any local configuration, dependency or build mutation.
  if [[ "${IOS_LOCK_WAIT:-1}" == "0" ]]; then
    exec python3 "$IOS_ROOT_DIR/scripts/ios_lock.py" --no-wait -- bash "$entrypoint" "$@"
  fi
  exec python3 "$IOS_ROOT_DIR/scripts/ios_lock.py" -- bash "$entrypoint" "$@"
}

ios_select_flutter() {
  local expected_version="$1"
  local pub_global_bin="${PUB_CACHE:-$HOME/.pub-cache}/bin"
  local flutter_output flutter_version
  flutter_command=()
  if [[ -n "${IOS_FLUTTER_BIN:-}" ]]; then
    flutter_command=("$IOS_FLUTTER_BIN")
  elif [[ -x "$IOS_ROOT_DIR/.fvm/flutter_sdk/bin/flutter" ]]; then
    flutter_command=("$IOS_ROOT_DIR/.fvm/flutter_sdk/bin/flutter")
  elif command -v fvm >/dev/null 2>&1; then
    flutter_command=(fvm flutter)
  elif [[ -x "$pub_global_bin/fvm" ]]; then
    flutter_command=("$pub_global_bin/fvm" flutter)
  else
    printf 'Flutter %s is unavailable; install the version pinned in .fvmrc or set IOS_FLUTTER_BIN.\n' "$expected_version" >&2
    return 1
  fi
  flutter_output="$("${flutter_command[@]}" --version 2>&1)" || {
    printf 'Could not run the project Flutter SDK: %s\n' "$flutter_output" >&2
    return 1
  }
  flutter_version="$(printf '%s\n' "$flutter_output" | sed -n 's/^Flutter \([^ ]*\).*/\1/p' | head -n 1)"
  if [[ "$flutter_version" != "$expected_version" ]]; then
    printf 'Expected Flutter %s; found %s.\n' "$expected_version" "${flutter_version:-unavailable}" >&2
    return 1
  fi
}
