#!/usr/bin/env ruby
# usage: ruby scripts/widget_share.rb <repo-relative path> [...]
# Adds files already in the project to the RhythmXWidget target's Sources phase.
require 'xcodeproj'
project = Xcodeproj::Project.open('RhythmX.xcodeproj')
widget = project.targets.find { |t| t.name == 'RhythmXWidget' } or abort('no widget target')
ARGV.each do |path|
  ref = project.files.find { |f| f.real_path.to_s.end_with?("/#{path}") } or abort("not in project: #{path}")
  widget.add_file_references([ref]) unless widget.source_build_phase.files_references.include?(ref)
end
project.save
