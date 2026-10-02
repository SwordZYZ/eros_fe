require 'fileutils'
require 'xcodeproj'

# Generate a disposable UI test runner; the production Xcode project is untouched.
destination = File.expand_path(ARGV.fetch(0))
FileUtils.mkdir_p(destination)
FileUtils.cp(File.join(__dir__, 'ShareMenuChecks.swift'), destination)
project = Xcodeproj::Project.new(File.join(destination, 'ShareMenuChecks.xcodeproj'))
target = project.new_target(:ui_test_bundle, 'ShareMenuChecks', :ios, '15.6')
target.source_build_phase.add_file_reference(project.main_group.new_file('ShareMenuChecks.swift'))
target.build_configurations.each do |configuration|
  configuration.build_settings.merge!({
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.fuhua.erosfe.share-menu-checks',
    'GENERATE_INFOPLIST_FILE' => 'YES',
    'SWIFT_VERSION' => '5.0',
    'TARGETED_DEVICE_FAMILY' => '1,2',
    'SDKROOT' => 'iphonesimulator',
    'CODE_SIGNING_ALLOWED' => 'NO',
  })
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(target)
scheme.add_test_target(target)
scheme.test_action.build_configuration = 'Debug'
scheme.save_as(project.path, 'ShareMenuChecks', true)
puts project.path
