#!/usr/bin/env ruby
# One-time: creates the RhythmXTests unit-test target, wires the existing test files, renames the scheme to RhythmX.
require 'xcodeproj'

project = Xcodeproj::Project.open('RhythmX.xcodeproj')
app = project.targets.find { |t| t.name == 'RhythmX' } or abort('no app target')
abort('RhythmXTests already exists') if project.targets.any? { |t| t.name == 'RhythmXTests' }

test = project.new_target(:unit_test_bundle, 'RhythmXTests', :ios, '18.0')
test.add_dependency(app)
test.build_configurations.each do |c|
  c.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'beta.Rhythm.tests'
  c.build_settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/RhythmX.app/RhythmX'
  c.build_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
  c.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  c.build_settings['SWIFT_VERSION'] = '5.0'
  c.build_settings['TARGETED_DEVICE_FAMILY'] = '1'
  c.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  c.build_settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
end

group = project.main_group['RhythmXTests'] || project.main_group.new_group('RhythmXTests', 'RhythmXTests')
Dir['RhythmXTests/*.swift'].sort.each do |f|
  ref = group.new_reference(File.basename(f))
  test.add_file_references([ref])
end
project.save

schemes_dir = File.join('RhythmX.xcodeproj', 'xcshareddata', 'xcschemes')
old = File.join(schemes_dir, 'Rhythm(x).xcscheme')
scheme = Xcodeproj::XCScheme.new(old)
scheme.add_test_target(test)
scheme.save_as('RhythmX.xcodeproj', 'RhythmX', true)
File.delete(old) if File.exist?(old)
puts 'ok'
