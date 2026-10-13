#!/usr/bin/env ruby
# One-time: creates the RhythmXWidget extension target, embeds it in the app, wires entitlements and 1.9.1 version.
require 'xcodeproj'

project = Xcodeproj::Project.open('RhythmX.xcodeproj')
app = project.targets.find { |t| t.name == 'RhythmX' } or abort('no app target')
abort('RhythmXWidget already exists') if project.targets.any? { |t| t.name == 'RhythmXWidget' }

widget = project.new_target(:app_extension, 'RhythmXWidget', :ios, '18.0')
widget.build_configurations.each do |c|
  s = c.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = 'beta.Rhythm.widget'
  s['PRODUCT_NAME'] = '$(TARGET_NAME)'
  s['INFOPLIST_FILE'] = 'RhythmXWidget/Info.plist'
  s['GENERATE_INFOPLIST_FILE'] = 'YES'
  s['INFOPLIST_KEY_CFBundleDisplayName'] = 'RhythmX'
  s['CODE_SIGN_ENTITLEMENTS'] = 'RhythmXWidget/RhythmXWidget.entitlements'
  s['CODE_SIGN_STYLE'] = 'Automatic'
  s['DEVELOPMENT_TEAM'] = 'P9Z5QB8965'
  s['SWIFT_VERSION'] = '5.0'
  s['TARGETED_DEVICE_FAMILY'] = '1'
  s['SKIP_INSTALL'] = 'YES'
  s['MARKETING_VERSION'] = '1.9.1'
  s['CURRENT_PROJECT_VERSION'] = '3'
  s['LD_RUNPATH_SEARCH_PATHS'] = '$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks'
end
widget.add_system_framework('WidgetKit')
widget.add_system_framework('SwiftUI')

# Widget-only sources
group = project.main_group['RhythmXWidget'] || project.main_group.new_group('RhythmXWidget', 'RhythmXWidget')
Dir['RhythmXWidget/*.swift'].sort.each { |f| widget.add_file_references([group.new_reference(File.basename(f))]) }
group.new_reference('Info.plist')
group.new_reference('RhythmXWidget.entitlements')

# Embed in app
app.add_dependency(widget)
embed = app.copy_files_build_phases.find { |p| p.name == 'Embed Foundation Extensions' } ||
        app.new_copy_files_build_phase('Embed Foundation Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
bf = embed.add_file_reference(widget.product_reference, true)
bf.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

# App entitlements + version bump
app_group = project.main_group['RhythmX']
app_group.new_reference('RhythmX.entitlements') unless app_group.files.any? { |f| f.path == 'RhythmX.entitlements' }
app.build_configurations.each do |c|
  c.build_settings['CODE_SIGN_ENTITLEMENTS'] = 'RhythmX/RhythmX.entitlements'
  c.build_settings['MARKETING_VERSION'] = '1.9.1'
  c.build_settings['CURRENT_PROJECT_VERSION'] = '3'
end

project.save
puts 'ok'
