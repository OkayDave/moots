# frozen_string_literal: true

if ENV["COVERAGE"] == "1"
  require "simplecov"
  SimpleCov.start do
    enable_coverage :branch
    cover "lib/**/*.rb"
    # Bundler evaluates this release metadata before SimpleCov starts.
    skip "/lib/moots/version.rb"
    minimum_coverage line: 100, branch: 100
    coverage(:line) { minimum 100, per: :file }
    coverage(:branch) { minimum 100, per: :file }
  end
end

require "moots"
require "moots/cli"
require "tmpdir"
require "fileutils"
require "rbconfig"
require "stringio"

module ProjectHelpers
  def in_project
    Dir.mktmpdir("moots-spec-") do |directory|
      # macOS may return a /var alias while paths inside the project resolve through /private/var.
      Dir.chdir(directory) { yield Dir.pwd }
    end
  end

  def write_source(path = "example.rb", code = "a + b")
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, code)
    File.expand_path(path)
  end

  def ruby_command(code)
    [RbConfig.ruby, "-e", code]
  end

  def test_result(success, output = "")
    Moots::TestResult.new(success: success, output: output)
  end

  def capture_command(*command, timeout: 15)
    options = Gem.win_platform? ? { new_pgroup: true } : { pgroup: true }
    Open3.popen3(*command, **options) do |stdin, stdout, stderr, process|
      stdin.close
      readers = [stdout, stderr].map { |stream| Thread.new { stream.read } }
      begin
        Timeout.timeout(timeout) { [*readers.map(&:value), process.value] }
      ensure
        if process.alive?
          if Gem.win_platform?
            system("taskkill", "/PID", process.pid.to_s, "/T", "/F", out: File::NULL, err: File::NULL)
          else
            Process.kill("KILL", -process.pid)
          end
        end
        readers.each(&:kill)
        readers.each(&:join)
      end
    end
  end
end

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.fail_if_no_examples = true
  config.order = :random
  config.include ProjectHelpers
  config.expect_with(:rspec) { |expectations| expectations.syntax = :expect }
  config.mock_with(:rspec) { |mocks| mocks.verify_partial_doubles = true }
end
