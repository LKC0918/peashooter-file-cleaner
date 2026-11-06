# Shared, dependency-free checks for public source and release bundles.
require "zlib"

module ReleasePrivacy
  PNG_SIGNATURE = "\x89PNG\r\n\x1a\n".b.freeze
  PNG_CHUNKS = %w[IHDR PLTE tRNS IDAT IEND sRGB gAMA cHRM].freeze
  WAVE_CHUNKS = ["fmt ", "data", "fact"].freeze

  def self.asset_paths
    sequences = { "peashooter/idle/idle" => 12, "peashooter/shoot/shoot" => 11,
                  "impact/impact" => 4, "zombies/walk/zombie" => 16 }
    sequences.flat_map { |prefix, count| (1..count).map { |i| format("assets/%s_%02d.png", prefix, i) } } +
      ["assets/projectile/projectile_01.png"] + %w[firepea splat pop].map { |n| "assets/sounds/#{n}.wav" }
  end

  def self.png_chunks(bytes)
    raise "Invalid PNG header" unless bytes.start_with?(PNG_SIGNATURE)
    offset = 8
    chunks = []
    until offset == bytes.bytesize
      raise "Truncated PNG" if offset + 12 > bytes.bytesize
      length = bytes.byteslice(offset, 4).unpack1("N")
      kind = bytes.byteslice(offset + 4, 4)
      body = bytes.byteslice(offset + 8, length)
      crc = bytes.byteslice(offset + 8 + length, 4)
      raise "Invalid PNG chunk" unless body && crc && crc.bytesize == 4 && Zlib.crc32(kind + body) == crc.unpack1("N")
      chunks << [kind, bytes.byteslice(offset, length + 12)]
      offset += length + 12
      break if kind == "IEND"
    end
    raise "Invalid PNG structure" unless offset == bytes.bytesize && chunks.first&.first == "IHDR" &&
      chunks.last&.first == "IEND" && chunks.any? { |kind, _| kind == "IDAT" }
    chunks
  end

  def self.sanitize_png(bytes)
    PNG_SIGNATURE + png_chunks(bytes).select { |kind, _| PNG_CHUNKS.include?(kind) }.map(&:last).join
  end

  def self.wave_chunks(bytes)
    raise "Invalid WAV header" unless bytes.byteslice(0, 4) == "RIFF" && bytes.byteslice(8, 4) == "WAVE" &&
      bytes.byteslice(4, 4).unpack1("V") + 8 == bytes.bytesize
    offset = 12
    chunks = []
    while offset < bytes.bytesize
      raise "Truncated WAV" if offset + 8 > bytes.bytesize
      kind = bytes.byteslice(offset, 4)
      size = bytes.byteslice(offset + 4, 4).unpack1("V")
      length = 8 + size + size % 2
      raise "Invalid WAV chunk" if offset + length > bytes.bytesize
      chunks << [kind, bytes.byteslice(offset, length)]
      offset += length
    end
    raise "WAV data or format missing" unless %w[data].all? { |k| chunks.any? { |kind, _| kind == k } } &&
      chunks.any? { |kind, _| kind == "fmt " }
    chunks
  end

  def self.sanitize_wave(bytes)
    body = "WAVE" + wave_chunks(bytes).select { |kind, _| WAVE_CHUNKS.include?(kind) }.map(&:last).join
    "RIFF" + [body.bytesize].pack("V") + body
  end

  def self.check_asset(path, bytes)
    case File.extname(path)
    when ".png"
      raise "PNG contains non-rendering metadata" unless png_chunks(bytes).all? { |kind, _| PNG_CHUNKS.include?(kind) }
    when ".wav"
      raise "WAV contains extra metadata" unless wave_chunks(bytes).all? { |kind, _| WAVE_CHUNKS.include?(kind) }
    when ".icns"
      raise "Invalid ICNS" unless bytes.byteslice(0, 4) == "icns" && bytes.byteslice(4, 4).unpack1("N") == bytes.bytesize
      offset = 8
      allowed = %w[icp4 icp5 icp6 ic07 ic08 ic09 ic10 ic11 ic12 ic13 ic14]
      while offset < bytes.bytesize
        kind = bytes.byteslice(offset, 4)
        length = bytes.byteslice(offset + 4, 4)&.unpack1("N")
        raise "Unexpected icon chunk" unless allowed.include?(kind) && length && length >= 8 && offset + length <= bytes.bytesize
        check_asset("icon.png", bytes.byteslice(offset + 8, length - 8))
        offset += length
      end
      raise "Invalid ICNS length" unless offset == bytes.bytesize
    else
      raise "Not an approved asset format"
    end
  end

  def self.sanitize_icns(bytes)
    raise "Invalid ICNS" unless bytes.byteslice(0, 4) == "icns" && bytes.byteslice(4, 4).unpack1("N") == bytes.bytesize
    offset = 8
    body = "".b
    while offset < bytes.bytesize
      kind = bytes.byteslice(offset, 4)
      length = bytes.byteslice(offset + 4, 4)&.unpack1("N")
      raise "Invalid icon chunk length" unless length && length >= 8 && offset + length <= bytes.bytesize
      if %w[icp4 icp5 icp6 ic07 ic08 ic09 ic10 ic11 ic12 ic13 ic14].include?(kind)
        png = sanitize_png(bytes.byteslice(offset + 8, length - 8))
        body << kind << [png.bytesize + 8].pack("N") << png
      end
      offset += length
    end
    raise "No approved PNG icons" if body.empty?
    "icns" + [body.bytesize + 8].pack("N") + body
  end

  def self.text_issues(bytes)
    text = bytes.b
    checks = {
      "private key" => /-----BEGIN (?:[A-Z0-9]+ )?PRIVATE KEY-----/n,
      "credential-like token" => /(?:github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9_-]{20,}|AKIA[A-Z0-9]{16})/n,
      "personal home path" => Regexp.new('/' + 'Users/(?!test(?:/|\\b))[^\\s/"\'<>\\x00]+/', Regexp::NOENCODING),
      "temporary machine path" => Regexp.new('(?:/private)?/var/' + 'folders/', Regexp::NOENCODING),
      "mounted volume path" => Regexp.new('/' + 'Volumes/[^\\s"\'\\x00]+/', Regexp::NOENCODING),
      "phone-like value" => /(?<![A-Za-z0-9])1[3-9][0-9]{9}(?![A-Za-z0-9])/n,
      "identity-number-like value" => /(?<![A-Za-z0-9])[1-9][0-9]{16}[0-9Xx](?![A-Za-z0-9])/n
    }
    found = checks.select { |name, pattern| text.match?(pattern) }.keys
    text.scan(/[A-Za-z0-9_.+%-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/n).uniq.each do |email|
      found << "personal-email-like value" unless email.end_with?("@users.noreply.github.com") || email == "noreply@github.com"
    end
    found.uniq
  end
end
