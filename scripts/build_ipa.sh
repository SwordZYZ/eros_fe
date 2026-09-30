source ./para.sh
ios_flutter_bin="$scripts_path/../.fvm/flutter_sdk/bin/flutter"
cd $scripts_path/../ios && bundle exec pod install --deployment && cd $scripts_path
bundle exec "$ios_flutter_bin" build ipa --release && sh reid.sh && sh zip.sh $version
