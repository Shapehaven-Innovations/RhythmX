#!/usr/bin/env ruby
# usage: ruby scripts/xcode_add.rb <target> <repo-relative path> [...]
# Registers existing files in project.pbxproj under the group chain that mirrors their folders.
# Groups are matched by name or path (some groups, e.g. Services/Components, have a name but no path,
# and their file refs carry the folder-relative path, e.g. "Services/ICSExporter.swift").
require 'xcodeproj'
require 'pathname'

project = Xcodeproj::Project.open('RhythmX.xcodeproj')
target = project.targets.find { |t| t.name == ARGV[0] } or abort("no target #{ARGV[0]}")
root = Pathname.new(Dir.pwd)

ARGV[1..].each do |path|
  abort("missing file #{path}") unless File.exist?(path)
  group = project.main_group
  File.dirname(path).split('/').each do |part|
    group = group[part] || group.new_group(part, part)
  end
  abs = root + path
  rel = abs.relative_path_from(Pathname.new(group.real_path)).to_s
  next if group.files.any? { |f| f.real_path.to_s == abs.to_s }
  ref = group.new_reference(rel)
  if %w[.xcprivacy .storyboard .xcassets].include?(File.extname(path))
    target.add_resources([ref])
  else
    target.add_file_references([ref])
  end
end
project.save
