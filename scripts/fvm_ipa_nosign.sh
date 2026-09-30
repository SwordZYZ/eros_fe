source ./para.sh
ios_flutter_bin="$scripts_path/../.fvm/flutter_sdk/bin/flutter"
cd $scripts_path/../ios && bundle exec pod install --deployment && cd $scripts_path
"$ios_flutter_bin" pub get --enforce-lockfile
bundle exec "$ios_flutter_bin" build ios --release --no-codesign && sh thin-payload.sh ${ios_nosign_path}
