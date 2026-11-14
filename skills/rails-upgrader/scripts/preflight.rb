#!/usr/bin/env ruby
# frozen_string_literal: true

# Preflight report for a Rails upgrade.
#
#   ruby preflight.rb [APP_DIR] [TARGET_RAILS]
#
#   APP_DIR       the application root (default: current directory)
#   TARGET_RAILS  e.g. 8.1 (default: the newest version listed below)
#
# Reads Gemfile.lock, .ruby-version and config/, then prints the current
# versions, whether the previous upgrade step was finished, and the ordered
# list of Rails steps to the target with the Ruby each one needs.
#
# Uses only the standard library and avoids newer syntax on purpose: it has to
# run inside applications still on Ruby 2.4.

require "rubygems"

# Minimum Ruby per Rails minor, from the "Ruby Versions" list in the official
# upgrade guide: https://guides.rubyonrails.org/upgrading_ruby_on_rails.html
RUBY_MINIMUM = {
  "5.0" => "2.2.2", "5.1" => "2.2.2", "5.2" => "2.2.2",
  "6.0" => "2.5.0", "6.1" => "2.5.0",
  "7.0" => "2.7.0", "7.1" => "2.7.0",
  "7.2" => "3.1.0",
  "8.0" => "3.2.0", "8.1" => "3.2.0"
}.freeze
LADDER = RUBY_MINIMUM.keys.freeze

# Newest Ruby minor that Rails' own CI hard-tests each line on; newer Rubies
# run there only as soft-fail jobs. From max_ruby in rails/buildkite-config:
# 2.7 for Rails < 6.1, 3.3 for Rails < 8, no cap from 8.0.
def ruby_ceiling(rails_minor)
  v = Gem::Version.new(rails_minor)
  return "2.7" if v < Gem::Version.new("6.1")
  return "3.3" if v < Gem::Version.new("8.0")
  nil
end

def minor(version)
  version.to_s.split(".").first(2).join(".")
end

def read(path)
  File.exist?(path) ? File.read(path) : nil
end

app = File.expand_path(ARGV[0] || Dir.pwd)
target = ARGV[1] || LADDER.last
lock = read(File.join(app, "Gemfile.lock"))
abort "No Gemfile.lock in #{app}. Run this from the application root." unless lock

rails = lock[/^    rails \(([\d.]+)\)/, 1] || lock[/^    railties \(([\d.]+)\)/, 1]
abort "Gemfile.lock lists neither rails nor railties." unless rails

ruby_file = read(File.join(app, ".ruby-version"))
ruby_tool = read(File.join(app, ".tool-versions"))
ruby_lock = lock[/^RUBY VERSION\s+ruby ([\d.]+)/, 1]
ruby = (ruby_file && ruby_file[/[\d]+\.[\d]+(\.[\d]+)?/]) ||
       (ruby_tool && ruby_tool[/^ruby ([\d.]+)/, 1]) || ruby_lock

application_rb = read(File.join(app, "config", "application.rb")) || ""
load_defaults = application_rb[/^\s*config\.load_defaults\s+["']?([\d.]+)/, 1]
classic = application_rb =~ /^\s*config\.autoloader\s*=\s*:classic/
leftover = Dir.glob(File.join(app, "config", "initializers", "new_framework_defaults*.rb"))

playbook = File.expand_path(ENV["RAILS_UPGRADE_PLAYBOOK"] || "~/.claude/rails-upgrade-playbook")
playbook = nil unless File.directory?(File.join(playbook, "steps"))

puts "Rails #{rails} (#{minor(rails)})   Ruby #{ruby || 'unknown'}" \
     "#{ruby_lock && ruby && ruby_lock != ruby ? " (Gemfile.lock says #{ruby_lock})" : ''}"
puts "config.load_defaults #{load_defaults || 'not set'}"
puts "Playbook: #{playbook || 'none found (set RAILS_UPGRADE_PLAYBOOK); use the official guide'}"
puts

problems = []
if load_defaults && Gem::Version.new(load_defaults) < Gem::Version.new(minor(rails))
  problems << "load_defaults #{load_defaults} is behind Rails #{minor(rails)}: the #{minor(rails)} " \
              "framework defaults are not all adopted. Finish them before starting the next step."
end
leftover.each do |file|
  problems << "#{file.sub(app + '/', '')} still exists: a previous step's defaults are unfinished."
end
problems << "config.autoloader = :classic is set: migrate to Zeitwerk before leaving 6.x." if classic
if ruby_lock && ruby && minor(ruby_lock) != minor(ruby)
  problems << ".ruby-version and Gemfile.lock disagree; settle the Ruby version first."
end

ceiling = ruby_ceiling(minor(rails))
if ruby && ceiling && Gem::Version.new(minor(ruby)) > Gem::Version.new(ceiling)
  problems << "Ruby #{ruby} is newer than Rails #{minor(rails)} is tested on (up to #{ceiling}). " \
              "Expect breakage, or move Rails first."
end

unless problems.empty?
  puts "Finish first:"
  problems.each { |p| puts "  - #{p}" }
  puts
end

from = LADDER.index(minor(rails))
to = LADDER.index(minor(target))
if from.nil? || to.nil?
  puts "Rails #{minor(rails)} or target #{target} is outside #{LADDER.first}..#{LADDER.last}; " \
       "work from the official guide."
  exit
end
if to <= from
  puts "Already at or past #{target}."
  exit
end

puts "Steps to Rails #{minor(target)} (#{to - from}), in order:"
current_ruby = ruby && Gem::Version.new(ruby)
LADDER[from..to].each_cons(2) do |a, b|
  need = Gem::Version.new(RUBY_MINIMUM[b])
  cap = ruby_ceiling(b)
  line = "  #{a} -> #{b}   Ruby >= #{RUBY_MINIMUM[b]}#{cap ? ", tested up to #{cap}" : ''}"
  if current_ruby && current_ruby < need
    line += "   <- Ruby step first (on Rails #{a}, its own deploy)"
    current_ruby = need
  end
  if playbook
    file = File.join(playbook, "steps", "rails-#{a}-to-#{b}.md")
    line += File.exist?(file) ? "   playbook: steps/#{File.basename(file)}" : "   playbook: no file"
  end
  puts line
end
puts
puts "Minimums are from the official upgrade guide; \"tested up to\" is Rails' CI ceiling. " \
     "Move Ruby no further than the current Rails is tested on#{playbook ? ' (playbook: ruby/compatibility.md)' : ''}."
