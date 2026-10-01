#!/usr/bin/env bash

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/ios_common.sh"

usage() {
  printf 'Usage: %s prepare [--simulator|--device]\n' "$0" >&2
  printf '       %s pods [pod install arguments]\n' "$0" >&2
  printf '       %s build {ios|ipa} [Flutter build arguments]\n' "$0" >&2
  printf '       %s run [Flutter run arguments]\n' "$0" >&2
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
case "$operation" in
  prepare)
    bash "$SCRIPT_DIR/ios_prepare.sh" "$@"
    ;;
  pods)
    cd ios
    bundle exec pod install --deployment "$@"
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
    bundle exec "${flutter_command[@]}" build "$target" --no-pub "$@"
    ;;
  run)
    ios_select_flutter 3.47.3
    bundle exec "${flutter_command[@]}" run --no-pub "$@"
    ;;
  *) usage; exit 2 ;;
esac
