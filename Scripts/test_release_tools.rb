#!/usr/bin/env ruby
require_relative "release_privacy"

count = 0
assert = lambda do |description, &test|
  abort "FAIL: #{description}" unless test.call
  count += 1
end
assert.call("synthetic personal path is rejected") { !ReleasePrivacy.text_issues('/Users/' + 'privacy-fixture/file.txt').empty? }
assert.call("temporary paths are rejected") { !ReleasePrivacy.text_issues('/var/' + 'folders/synthetic').empty? }
assert.call("synthetic email is rejected") { !ReleasePrivacy.text_issues(['private', 'example.test'].join('@')).empty? }
assert.call("synthetic token is rejected") { !ReleasePrivacy.text_issues('ghp_' + 'a' * 40).empty? }
assert.call("synthetic test path is allowed") { ReleasePrivacy.text_issues('/Users/test/file.txt').empty? }
assert.call("hidden GitHub email is allowed") { ReleasePrivacy.text_issues('demo@users.noreply.github.com').empty? }
chunk = lambda { |kind, body| [body.bytesize].pack('N') + kind + body + [Zlib.crc32(kind + body)].pack('N') }
pixels = Zlib.deflate("\x00\x00\xff\x00\xff".b)
png = ReleasePrivacy::PNG_SIGNATURE + chunk.call('IHDR', [1, 1, 8, 6, 0, 0, 0].pack('NNC5')) +
  chunk.call('tEXt', "Author\0" + ['private', 'example.test'].join('@')) +
  chunk.call('IDAT', pixels) + chunk.call('IEND', '')
clean = ReleasePrivacy.sanitize_png(png)
assert.call("PNG metadata is removed") { !clean.include?('Author') && clean.include?(pixels) }
assert.call("sanitized PNG passes validation") { ReleasePrivacy.check_asset('test.png', clean).nil? }
assert.call("PNG with text metadata is rejected") do
  begin; ReleasePrivacy.check_asset('test.png', png); false; rescue; true; end
end
wave_chunk = lambda { |kind, body| kind + [body.bytesize].pack('V') + body + (body.bytesize.odd? ? "\0" : '') }
body = 'WAVE' + wave_chunk.call('fmt ', [1, 1, 8000, 8000, 1, 8].pack('vvVVvv')) +
  wave_chunk.call('LIST', 'synthetic metadata') + wave_chunk.call('data', "\x80\x81".b)
wave = 'RIFF' + [body.bytesize].pack('V') + body
clean_wave = ReleasePrivacy.sanitize_wave(wave)
assert.call("WAV metadata is removed, audio retained") { !clean_wave.include?('LIST') && clean_wave.end_with?("\x80\x81".b) }
assert.call("sanitized WAV passes validation") { ReleasePrivacy.check_asset('test.wav', clean_wave).nil? }
icon_body = 'ic07' + [png.bytesize + 8].pack('N') + png + 'info' + [12].pack('N') + 'data'
icon = 'icns' + [icon_body.bytesize + 8].pack('N') + icon_body
clean_icon = ReleasePrivacy.sanitize_icns(icon)
assert.call("ICNS metadata is removed") { !clean_icon.include?('info') && !clean_icon.include?('Author') }
assert.call("sanitized icon passes validation") { ReleasePrivacy.check_asset('test.icns', clean_icon).nil? }
assert.call("malformed image is rejected") do
  begin; ReleasePrivacy.sanitize_png('not an image'); false; rescue; true; end
end
assert.call("only required runtime assets are listed") { ReleasePrivacy.asset_paths.length == 47 && ReleasePrivacy.asset_paths.none? { |p| p.include?('helmet') } }
puts "Release tooling tests: #{count} passed (synthetic in-memory data only)."
