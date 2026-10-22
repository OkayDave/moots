# frozen_string_literal: true

require "timeout"

RSpec.describe "Reporting through the executable" do
  let(:executable) { File.expand_path("../exe/moots", __dir__) }
  let(:library) { File.expand_path("../lib", __dir__) }

  def command(*arguments)
    [RbConfig.ruby, "-I", library, executable, *arguments]
  end

  def configure(test_command, path = ".moots.yml", **options)
    File.write(path, { "include" => ["math.rb"], "test_command" => test_command, **options }.to_yaml)
  end

  it "flushes baseline and mutation progress while the test subprocess is still blocked" do
    in_project do |directory|
      path = write_source("math.rb", "VALUE = 1 + 2")
      write_source("check.rb", <<~RUBY)
        require_relative "math"
        release = File.join(#{directory.dump}, VALUE == 3 ? "release-baseline" : "release-mutation")
        sleep 0.01 until File.exist?(release)
      RUBY
      configure([RbConfig.ruby, "check.rb"])
      Open3.popen3(*command) do |stdin, stdout, stderr, process|
        stdin.close
        begin
          Timeout.timeout(10) do
            expect(stdout.readline).to eq("Preparing isolated working copy...\n")
            expect(stdout.readline).to eq("Running baseline tests...\n")
            File.write("release-baseline", "")
            expect(stdout.readline).to eq("Baseline passed.\n")
            expect(stdout.readline).to match(%r{\A\[1/1\] Testing [0-9a-f]{16} math.rb:1\n\z})
            expect(process).to be_alive
          end
        ensure
          File.write("release-baseline", "")
          File.write("release-mutation", "")
        end
        expect(stdout.read).to include("SURVIVED", "1 mutations, 0 killed, 1 survived")
        expect(stderr.read).to eq("")
        expect(process.value.exitstatus).to eq(1)
      end
      expect(File.binread(path)).to eq("VALUE = 1 + 2")
    end
  end

  it "produces clean JSON despite noisy tests and reruns the exact reported mutation" do
    in_project do |directory|
      source = "VALUES = [1 + 2, 4 > 3]"
      path = write_source("math.rb", source)
      write_source("check.rb", <<~RUBY)
        require_relative "math"
        File.open(#{File.join(directory, "invocations").dump}, "a") { |file| file.puts(File.binread("math.rb")) }
        puts "test chatter"
      RUBY
      configure([RbConfig.ruby, "check.rb"], "config with spaces.yml")
      stdout, stderr, status = Open3.capture3(*command("--format", "json", "--config", "config with spaces.yml"))
      expect(status.exitstatus).to eq(1), stderr
      report = JSON.parse(stdout)
      expect(report).to include("status" => "completed", "schema_version" => 1)
      expect(report.fetch("summary")).to eq("mutations" => 2, "killed" => 0, "survived" => 2)
      expect(report.fetch("results").map { |item| item.fetch("test_output") }).to eq(["test chatter"] * 2)
      expect(stderr).to include("[1/2] Testing", "[2/2] Testing", "SURVIVED")
      selected = report.fetch("results").last
      expect(selected.fetch("original")).to eq("4 > 3")
      File.write("invocations", "")
      # Replace only the installed executable prefix; pass reported arguments literally.
      stdout, stderr, status = Open3.capture3(*command("--format", "json", *selected.fetch("rerun").drop(3)))
      expect(status.exitstatus).to eq(1), stderr
      repeated = JSON.parse(stdout)
      expect(repeated.fetch("results")).to eq([selected])
      expect(File.readlines("invocations", chomp: true)).to eq([source, "VALUES = [1 + 2, 4 >= 3]"])
      expect(File.binread(path)).to eq(source)
    end
  end

  it "emits a JSON error for a failed baseline without changing the source" do
    in_project do
      path = write_source("math.rb", "VALUE = 1 + 2")
      configure(ruby_command('abort "broken baseline"'))
      stdout, stderr, status = Open3.capture3(*command("--format", "json"))
      expect(status.exitstatus).to eq(2)
      report = JSON.parse(stdout)
      expect(report).to include("status" => "error", "results" => [])
      expect(report.fetch("error")).to include("Baseline tests failed", "broken baseline")
      expect(stderr).not_to include("Testing ")
      expect(File.binread(path)).to eq("VALUE = 1 + 2")
    end
  end
end
