#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/ios_common.sh"
ios_require_project_lock "$SCRIPT_DIR/build_ipa.sh" "$@"
cd "$SCRIPT_DIR"
source ./para.sh
ios_flutter_bin="$scripts_path/../.fvm/flutter_sdk/bin/flutter"
cd "$scripts_path/../ios"
bundle exec pod install --deployment
cd "$scripts_path"
bundle exec "$ios_flutter_bin" build ipa --release && sh reid.sh && sh zip.sh $version
