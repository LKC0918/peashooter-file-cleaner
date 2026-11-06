#!/usr/bin/env ruby
# Inspect the upload candidate without opening excluded runtime or build data.
require "find"
require "uri"
require_relative "release_privacy"

root = File.expand_path("..", __dir__)
allowed_extensions = %w[.swift .sh .rb .md .plist .entitlements .pbxproj .xcscheme .wflow .html]
allowed_dotfiles = %w[.gitignore .gitattributes]
generated_directories = %w[.git Build DerivedData build dist]
files = []
failures = []

Find.find(root) do |absolute|
  relative = absolute.delete_prefix(root + "/")
  next if absolute == root
  if File.symlink?(absolute)
    failures << "#{relative}: symbolic links are not part of the public snapshot"
    Find.prune if File.directory?(absolute)
    next
  end
  if File.directory?(absolute)
    Find.prune if generated_directories.include?(relative.split("/").first)
    next
  end
  files << relative
  if (ReleasePrivacy.asset_paths.map { |p| "Resources/#{p}" } + ["Resources/AppIcon.icns"]).include?(relative)
    begin
      bytes = File.binread(absolute)
      ReleasePrivacy.check_asset(relative, bytes)
      ReleasePrivacy.text_issues(bytes).each { |issue| failures << "#{relative}: #{issue}" }
    rescue => error
      failures << "#{relative}: #{error.message}"
    end
    next
  end
  if ["Distribution/version.txt", ".github/workflows/release.yml"].include?(relative)
    source = File.binread(absolute)
    ReleasePrivacy.text_issues(source).each { |issue| failures << "#{relative}: #{issue}" }
    next
  end
  unless allowed_dotfiles.include?(relative) || allowed_extensions.include?(File.extname(relative))
    failures << "#{relative}: unexpected file type"
    next
  end
  if relative.match?(%r{(?:\A|/)(?:\.claude|\.codex|\.aws|\.ssh|xcuserdata)(?:/|\z)})
    failures << "#{relative}: local settings or credentials directory"
  end

  source = File.read(absolute, encoding: "UTF-8")
  unless source.valid_encoding? && !source.include?("\u0000")
    failures << "#{relative}: not plain UTF-8 text"
    next
  end
  ReleasePrivacy.text_issues(source).each { |issue| failures << "#{relative}: #{issue}" }
end

abort failures.uniq.sort.join("\n") unless failures.empty?
puts "Public snapshot: #{files.length} allowlisted source, documentation and sanitized asset files checked"
puts "Personal paths, email-like values, credentials and unexpected files: no matches"
puts "Review changes manually before publishing; pattern checks are not a guarantee."
