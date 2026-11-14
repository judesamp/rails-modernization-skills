#!/usr/bin/env ruby
# frozen_string_literal: true

# Deduplicate deprecation warnings into a ranked list of distinct messages.
#
#   ruby warnings.rb [--sites] [--match REGEX] [LOG ...]   (or pipe output in)
#
#   --sites        under each message, list up to 5 distinct call sites
#   --match REGEX  only keep messages matching REGEX (e.g. --match keyword)
#
# Reads Rails "DEPRECATION WARNING:" lines and Ruby "file:line: warning:"
# lines. Strips call-site details so one deprecated call in a shared helper
# counts once, not once per test that reached it.
#
# Standard library only; runs on Ruby 2.4+.

SITES_SHOWN = 5 # enough to see whether a message comes from one helper or many

show_sites = ARGV.delete("--sites")
match = nil
if (i = ARGV.index("--match"))
  match = Regexp.new(ARGV[i + 1].to_s, Regexp::IGNORECASE)
  ARGV.slice!(i, 2)
end

counts = Hash.new(0)
sites = Hash.new { |h, k| h[k] = Hash.new(0) }

ARGF.each_line do |raw|
  line = raw.scrub.strip
  if (m = line.match(/DEPRECATION WARNING:\s*(.*?)(?:\s*\(called from (.*?)\))?\.?\s*$/))
    message = m[1]
    site = m[2]
  elsif (m = line.match(/^(.+?:\d+): warning: (.*)$/))
    site = m[1]
    message = m[2]
  else
    next
  end
  message = message.gsub(/\s+/, " ").sub(/\.\z/, "")
  next if match && message !~ match

  counts[message] += 1
  sites[message][site.sub(%r{\A.*?/(app|lib|config|spec|test)/}, '\1/')] += 1 if site
end

if counts.empty?
  puts "No deprecation warnings found."
  exit
end

total = counts.values.inject(0, :+)
puts "#{counts.size} distinct messages (#{total} lines)"
puts
counts.sort_by { |message, n| [-n, message] }.each do |message, n|
  puts format("%6d  %s", n, message)
  next unless show_sites

  sites[message].sort_by { |s, c| [-c, s] }.first(SITES_SHOWN).each do |s, c|
    puts format("          %5d  %s", c, s)
  end
end
