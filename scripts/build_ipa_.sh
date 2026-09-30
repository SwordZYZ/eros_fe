source ./para.sh
cd $scripts_path/../ios && bundle exec pod install --deployment && cd $scripts_path
bundle exec fvm flutter build ipa --release && sh zip.sh $version
