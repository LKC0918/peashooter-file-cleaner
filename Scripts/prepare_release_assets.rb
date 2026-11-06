#!/usr/bin/env ruby
# Copy only runtime artwork; preserve pixel/audio data, discard descriptive metadata.
require "fileutils"
require "tmpdir"
require "open3"
require_relative "release_privacy"

abort "Usage: ruby Scripts/prepare_release_assets.rb SOURCE_PROJECT --authorized" unless ARGV.length == 2 && ARGV[1] == "--authorized"
source = File.realpath(ARGV[0])
root = File.expand_path("..", __dir__)
abort "Use a separate source project" if source == root
paths = ReleasePrivacy.asset_paths
paths.each do |relative|
  input = File.join(source, "Resources", relative)
  abort "Missing asset: #{relative}" unless File.file?(input) && !File.symlink?(input)
  bytes = File.binread(input)
  clean = relative.end_with?(".png") ? ReleasePrivacy.sanitize_png(bytes) : ReleasePrivacy.sanitize_wave(bytes)
  ReleasePrivacy.check_asset(relative, clean)
  abort "Asset failed privacy patterns: #{relative}" unless ReleasePrivacy.text_issues(clean).empty?
  destination = File.join(root, "Resources", relative)
  FileUtils.mkdir_p(File.dirname(destination))
  if File.exist?(destination)
    abort "Refusing to overwrite changed asset: #{relative}" unless File.binread(destination) == clean
    next
  end
  File.binwrite(destination, clean)
end

# Decode the old icon to neutral PNGs and build a fresh icon container, retaining no source metadata.
scratch = Dir.mktmpdir("peashooter-public-icon-")
iconset = File.join(scratch, "AppIcon.iconset")
out, status = Open3.capture2e("/usr/bin/iconutil", "-c", "iconset", "-o", iconset, File.join(source, "Resources/AppIcon.icns"))
abort "Icon conversion failed" unless status.success?
Dir.glob(File.join(iconset, "*.png")).each do |png|
  File.binwrite(png, ReleasePrivacy.sanitize_png(File.binread(png)))
end
destination = File.join(root, "Resources/AppIcon.icns")
abort "Refusing to overwrite existing icon" if File.exist?(destination)
_, status = Open3.capture2e("/usr/bin/iconutil", "-c", "icns", "-o", destination, iconset)
abort "Icon assembly failed" unless status.success?
File.binwrite(destination, ReleasePrivacy.sanitize_icns(File.binread(destination)))
ReleasePrivacy.check_asset(destination, File.binread(destination))
abort "Icon failed privacy patterns" unless ReleasePrivacy.text_issues(File.binread(destination)).empty?
puts "Prepared #{paths.length} runtime assets and one application icon; text metadata removed."
puts "Original source files were not modified."
