#!/usr/bin/env ruby
require "find"
require "open3"
require_relative "release_privacy"

abort "Usage: ruby Scripts/verify_release.rb APP_PATH" unless ARGV.length == 1
app = File.realpath(ARGV[0])
extension = "Contents/PlugIns/PeashooterFinderExtension.appex/Contents"
text_files = ["Contents/Info.plist", "Contents/PkgInfo", "Contents/Resources/UserGuide.html",
              "Contents/Resources/THIRD_PARTY_NOTICES.md", "Contents/Resources/assets/README.md",
              "Contents/Resources/召唤豌豆射手.workflow/Contents/Info.plist",
              "Contents/Resources/召唤豌豆射手.workflow/Contents/Resources/document.wflow",
              "#{extension}/Info.plist", "#{extension}/PkgInfo"]
binaries = ["Contents/MacOS/Peashooter File Cleaner", "#{extension}/MacOS/PeashooterFinderExtension"]
assets = ReleasePrivacy.asset_paths.map { |p| "Contents/Resources/#{p}" } + ["Contents/Resources/AppIcon.icns"]
signatures = ["Contents/_CodeSignature/CodeResources", "#{extension}/_CodeSignature/CodeResources"]
approved = text_files + binaries + assets + signatures
found = []
errors = []
Find.find(app) do |path|
  next if path == app
  relative = path.delete_prefix(app + "/")
  if File.symlink?(path)
    errors << "#{relative}: unexpected symlink"
    Find.prune if File.directory?(path)
    next
  end
  next if File.directory?(path)
  found << relative
  unless approved.include?(relative)
    errors << "#{relative}: unapproved bundle file"
    next
  end
  bytes = File.binread(path)
  ReleasePrivacy.text_issues(bytes).each { |issue| errors << "#{relative}: #{issue}" }
  if assets.include?(relative)
    begin
      ReleasePrivacy.check_asset(relative, bytes)
    rescue => error
      errors << "#{relative}: #{error.message}"
    end
  end
end
required = (text_files - ["#{extension}/PkgInfo"]) + binaries + assets + signatures
(required - found).each { |path| errors << "Missing: #{path}" }
binaries.each do |relative|
  path = File.join(app, relative)
  next unless File.file?(path)
  archs, status = Open3.capture2e("/usr/bin/lipo", "-archs", path)
  errors << "#{relative}: not universal arm64 + x86_64" unless status.success? && archs.split.sort == %w[arm64 x86_64].sort
end
[app, File.join(app, "Contents/PlugIns/PeashooterFinderExtension.appex")].each do |bundle|
  _, status = Open3.capture2e("/usr/bin/codesign", "--verify", "--strict", bundle)
  errors << "Code signature verification failed" unless status.success?
  details, = Open3.capture2e("/usr/bin/codesign", "-dv", "--verbose=4", bundle)
  errors << "Expected anonymous ad-hoc signature" unless details.include?("Signature=adhoc") && details.include?("TeamIdentifier=not set")
  entitlements, = Open3.capture2e("/usr/bin/codesign", "-d", "--entitlements", ":-", bundle)
  errors << "Debug entitlement must not ship" if entitlements.include?("get-task-allow")
end
abort errors.uniq.join("\n") unless errors.empty?
puts "Release verified: #{found.length} allowlisted files; universal app and Finder extension."
puts "Anonymous ad-hoc signatures verified; no debug entitlement or private-path patterns."
puts "Not notarized; clean-machine Gatekeeper and Finder permissions still require manual verification."
