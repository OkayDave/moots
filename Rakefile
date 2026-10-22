# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new

desc "Run specs with 100% line and branch coverage requirements"
task :coverage do
  sh({ "COVERAGE" => "1" }, "bundle", "exec", "rspec")
end

desc "Dogfood Moots against every library file (fails on survivors or zero mutations)"
task :mutation do
  sh({ "COVERAGE" => nil }, RbConfig.ruby, "-Ilib", "exe/moots")
end

desc "Run lint, coverage, and self-mutation checks"
task verify: %i[rubocop coverage mutation]

task default: %i[spec]
