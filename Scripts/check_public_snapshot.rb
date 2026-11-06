#!/usr/bin/env ruby
# Inspect the upload candidate without opening excluded runtime or build data.
require "find"
require "uri"

root = File.expand_path("..", __dir__)
allowed_extensions = %w[.swift .sh .rb .md .plist .entitlements .pbxproj .xcscheme .wflow]
allowed_dotfiles = %w[.gitignore .gitattributes]
generated_directories = %w[.git Build DerivedData build]
files = []
failures = []

Find.find(root) do |absolute|
  relative = absolute.delete_prefix(root + "/")
  next if absolute == root
  if File.directory?(absolute)
    Find.prune if generated_directories.include?(relative.split("/").first)
    next
  end
  if File.symlink?(absolute)
    failures << "#{relative}: symbolic links are not part of the public snapshot"
    next
  end
  files << relative
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
  checks = {
    "private key" => /-----BEGIN (?:[A-Z0-9]+ )?PRIVATE KEY-----/,
    "credential-like token" => /(?:github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9_-]{20,}|AKIA[A-Z0-9]{16})/,
    "personal home path" => %r{/Users/(?!test(?:/|\b))[A-Za-z0-9_.\-\p{Han}]+/},
    "mounted volume path" => %r{/Volumes/[^\s"']+/},
    "phone-like value" => /(?<![A-Za-z0-9])1[3-9][0-9]{9}(?![A-Za-z0-9])/,
    "identity-number-like value" => /(?<![A-Za-z0-9])[1-9][0-9]{16}[0-9Xx](?![A-Za-z0-9])/
  }
  checks.each do |label, pattern|
    failures << "#{relative}: #{label}" if source.match?(pattern)
  end
  source.scan(/[A-Za-z0-9_.+%-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/).uniq.each do |email|
    unless email.end_with?("@users.noreply.github.com") || email == "noreply@github.com"
      failures << "#{relative}: personal-email-like value"
    end
  end
end

abort failures.uniq.sort.join("\n") unless failures.empty?
puts "Public snapshot: #{files.length} UTF-8 text files checked"
puts "Personal paths, email-like values, credentials and unexpected files: no matches"
puts "Review changes manually before publishing; pattern checks are not a guarantee."
