#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/ios_common.sh"
ios_require_project_lock "$SCRIPT_DIR/fvm_ipa_nosign.sh" "$@"
cd "$SCRIPT_DIR"
source ./para.sh
ios_flutter_bin="$scripts_path/../.fvm/flutter_sdk/bin/flutter"
cd "$scripts_path/../ios"
bundle exec pod install --deployment
cd "$scripts_path"
"$ios_flutter_bin" pub get --enforce-lockfile
bundle exec "$ios_flutter_bin" build ios --release --no-codesign && sh thin-payload.sh "$ios_nosign_path"
