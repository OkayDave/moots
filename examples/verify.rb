# frozen_string_literal: true

require "json"
require "open3"

def run_moots(config)
  stdout, stderr, status = Open3.capture3(
    "bundle", "exec", "moots", "--config", config, "--format", "json"
  )
  report = JSON.parse(stdout)
  [report, stderr, status]
rescue JSON::ParserError => e
  abort "Moots did not return JSON for #{config}: #{e.message}\n#{stdout}\n#{stderr}"
end

strong, strong_progress, strong_status = run_moots(".moots.yml")
strong_summary = strong.fetch("summary")
unless strong_status.success? && strong.fetch("status") == "completed" &&
       strong_summary.fetch("mutations").positive? && strong_summary.fetch("survived").zero?
  abort "Expected the strong suite to kill every mutation.\n#{strong_progress}\n#{strong}"
end

weak, weak_progress, weak_status = run_moots(".moots.weak.yml")
weak_summary = weak.fetch("summary")
unless weak_status.exitstatus == 1 && weak.fetch("status") == "completed" &&
       weak_summary.fetch("killed").positive? && weak_summary.fetch("survived").positive?
  abort "Expected the weak suite to expose both kills and survivors.\n#{weak_progress}\n#{weak}"
end

strong_killed = strong_summary.fetch("killed")
strong_mutations = strong_summary.fetch("mutations")
weak_killed = weak_summary.fetch("killed")
weak_survived = weak_summary.fetch("survived")

puts "Strong suite: #{strong_killed}/#{strong_mutations} killed"
puts "Weak suite: #{weak_killed} killed, #{weak_survived} survived"
