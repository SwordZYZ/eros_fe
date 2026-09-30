source ./para.sh
cd $scripts_path/../ios && bundle exec pod install --deployment && cd $scripts_path
fvm flutter pub get --enforce-lockfile
bundle exec fvm flutter build ios --release --no-codesign && sh thin-payload.sh ${ios_nosign_path}
