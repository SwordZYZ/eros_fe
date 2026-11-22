#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/ios_common.sh"

usage() {
  printf 'Usage: %s prepare [--simulator|--device]\n' "$0" >&2
  printf '       %s pods [pod install arguments]\n' "$0" >&2
  printf '       %s build {ios|ipa} [Flutter build arguments]\n' "$0" >&2
  printf '       %s run [Flutter run arguments]\n' "$0" >&2
  printf '       %s check | ci [--release]\n' "$0" >&2
  printf '       %s smoke {--simulator|--device} {auto|UDID} [Flutter test arguments]\n' "$0" >&2
  printf '       %s logs {simulator|device} UDID BUNDLE_ID\n' "$0" >&2
  printf 'Set IOS_LOCK_WAIT=0 to reject a busy checkout instead of waiting.\n' >&2
}

if [[ $# -eq 0 ]]; then
  usage
  exit 2
fi
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
  usage
  exit 0
fi
ios_require_project_lock "$SCRIPT_DIR/ios_dev.sh" "$@"
cd "$IOS_ROOT_DIR"
operation="$1"
shift
IOS_LOG_DIR="${IOS_LOG_DIR:-$IOS_ROOT_DIR/artifacts/ios-dev}"
IOS_LOG_DIR="$(python3 -c 'from pathlib import Path; import sys; print(Path(sys.argv[1]).resolve())' "$IOS_LOG_DIR")"
export IOS_LOG_DIR
capture() {
  local label="$1"
  shift
  python3 "$IOS_ROOT_DIR/tool/ios_evidence.py" --label "$label" --output "$IOS_LOG_DIR" -- "$@"
}
case "$operation" in
  check)
    capture check bash "$SCRIPT_DIR/ios_env_check.sh" "$@"
    ;;
  prepare)
    capture prepare bash "$SCRIPT_DIR/ios_prepare.sh" "$@"
    ;;
  pods)
    cd ios
    capture pods bundle exec pod install --deployment "$@"
    ;;
  build)
    if [[ $# -eq 0 ]]; then
      usage
      exit 2
    fi
    if [[ "$1" != "ios" && "$1" != "ipa" ]]; then
      usage
      exit 2
    fi
    target="$1"
    shift
    ios_select_flutter 3.47.3
    capture build bundle exec "${flutter_command[@]}" build "$target" --no-pub "$@"
    ;;
  run)
    ios_select_flutter 3.47.3
    capture run bundle exec "${flutter_command[@]}" run --no-pub "$@"
    ;;
  smoke)
    if [[ $# -lt 2 ]]; then usage; exit 2; fi
    mode="$1"
    device="$2"
    shift 2
    case "$mode" in
      --simulator)
        device="$(python3 "$IOS_ROOT_DIR/tool/ios_simulator.py" "$device")"
        printf '[iOS smoke] %s Simulator ready\n' "$(date -u +%FT%TZ)" >&2
        ;;
      --device)
        if [[ "$device" == "auto" ]]; then
          printf 'Device smoke requires an explicit iPad/iPhone UDID.\n' >&2
          exit 2
        fi
        ;;
      *) usage; exit 2 ;;
    esac
    ios_select_flutter 3.47.3
    printf '[iOS smoke] %s Flutter selected, starting evidence capture\n' "$(date -u +%FT%TZ)" >&2
    python3 "$IOS_ROOT_DIR/tool/ios_evidence.py" --label smoke --device "$device" \
      --output "$IOS_LOG_DIR" -- bundle exec "${flutter_command[@]}" test \
      integration_test/ios_smoke_test.dart --no-pub -d "$device" --reporter expanded "$@"
    ;;
  logs)
    if [[ $# -ne 3 ]]; then usage; exit 2; fi
    capture logs python3 "$IOS_ROOT_DIR/tool/ios_logs.py" "$@" --output "$IOS_LOG_DIR"
    ;;
  ci)
    if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--release" ) ]]; then usage; exit 2; fi
    lock_hashes="$(shasum -a 256 pubspec.lock ios/Podfile.lock Gemfile.lock)"
    capture lock-tests python3 -m unittest discover -s tool/tests -v
    bash "$SCRIPT_DIR/ios_dev.sh" prepare --simulator
    bash "$SCRIPT_DIR/ios_dev.sh" check
    if [[ $# -eq 1 ]]; then
      bash "$SCRIPT_DIR/ios_dev.sh" build ios --simulator --debug
    fi
    bash "$SCRIPT_DIR/ios_dev.sh" smoke --simulator auto
    if [[ "$lock_hashes" != "$(shasum -a 256 pubspec.lock ios/Podfile.lock Gemfile.lock)" ]]; then
      printf 'Locked dependency files changed during CI.\n' >&2
      exit 1
    fi
    ;;
  *) usage; exit 2 ;;
esac
