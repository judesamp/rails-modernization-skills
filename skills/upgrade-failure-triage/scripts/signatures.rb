#!/usr/bin/env ruby
# frozen_string_literal: true

# Group test failures by signature instead of reading them one by one.
#
#   bin/rails test 2>&1 | ruby signatures.rb
#   bundle exec rspec 2>&1 | ruby signatures.rb
#   ruby signatures.rb saved_output.txt
#
# Understands Minitest ("Error:" / "Failure:" blocks) and RSpec ("1) ..."
# blocks). A signature is the exception class plus its message with object
# inspections, addresses and numbers blanked out, so the same root cause
# raised from forty tests counts once. Expectation failures are grouped by
# their first line plus the failing file.
#
# Standard library only; runs on Ruby 2.4+.

EXAMPLES_SHOWN = 3 # enough tests per signature to start reading

def normalize(text)
  text.to_s.strip
      .gsub(/#<[^<>]*(?:<[^<>]*>[^<>]*)*>/, "#<...>")
      .gsub(/0x[0-9a-f]+/i, "0x...")
      .gsub(/\b\d+\b/, "N")
      .gsub(/\s+/, " ")[0, 200]
end

failures = [] # [signature, test name]
lines = ARGF.read.scrub.lines.map(&:chomp)

# Minitest
lines.each_with_index do |line, i|
  next unless line =~ /^(Error|Failure):\s*$/

  kind = Regexp.last_match(1)
  test = lines[i + 1].to_s.sub(/:\s*$/, "")
  body = lines[i + 2].to_s
  if kind == "Error" && body =~ /^([A-Z][\w:]*):\s*(.*)$/
    failures << ["#{Regexp.last_match(1)}: #{normalize(Regexp.last_match(2))}", test]
  else
    file = test[/\[([^\]:]+)/, 1]
    failures << ["Assertion: #{normalize(body)}#{file ? "  (#{file})" : ''}", test]
  end
end

# RSpec
starts = []
lines.each_with_index { |line, i| starts << i if line =~ /^\s{1,4}\d+\) \S/ }
starts.each_with_index do |start, n|
  block = lines[start...(starts[n + 1] || lines.size)]
  test = block.first.sub(/^\s*\d+\)\s*/, "")
  klass_at = block.index { |l| l =~ /^\s+([A-Z][\w:]*(?:Error|Exception|Invalid|NotFound|Missing)[\w:]*):?\s*$/ }
  if klass_at
    klass = block[klass_at].strip.sub(/:$/, "")
    failures << ["#{klass}: #{normalize(block[klass_at + 1])}", test]
  else
    failure_line = block.find { |l| l =~ /Failure\/Error:/ }
    expectation = block.find { |l| l =~ /^\s+(expected|Expected)/ }
    file = block.map { |l| l[%r{# \./((?:spec|app|lib)/[^:]+)}, 1] }.compact.first
    text = expectation || failure_line.to_s.sub(/.*Failure\/Error:/, "")
    failures << ["Expectation: #{normalize(text)}#{file ? "  (#{file})" : ''}", test]
  end
end

if failures.empty?
  puts "No Minitest or RSpec failures recognized. Is this the full output, including stderr?"
  exit
end

groups = failures.group_by(&:first)
puts "#{failures.size} failures, #{groups.size} distinct signatures"
puts
groups.sort_by { |sig, items| [-items.size, sig] }.each do |sig, items|
  puts format("%5d  %s", items.size, sig)
  items.map(&:last).uniq.first(EXAMPLES_SHOWN).each { |t| puts "         e.g. #{t}" }
end
