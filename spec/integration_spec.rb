# frozen_string_literal: true

RSpec.describe "Moots end to end" do
  let(:executable) { File.expand_path("../exe/moots", __dir__) }
  let(:library) { File.expand_path("../lib", __dir__) }

  it "kills every arithmetic and boolean mutation using a real test process" do
    in_project do
      code = <<~RUBY
        def calculate(a, b)
          [a + b, a - b, a * b, a / b]
        end
        def both(a, b) = a && b
        def either(a, b) = a || b
      RUBY
      path = write_source("math.rb", code)
      check = <<~RUBY
        require_relative "math"
        abort "arithmetic" unless calculate(8, 2) == [10, 6, 16, 4]
        [true, false].product([true, false]).each do |a, b|
          abort "and" unless both(a, b) == (a && b)
          abort "or" unless either(a, b) == (a || b)
        end
      RUBY
      write_source("checks.rb", check)
      results = Moots.run(include: ["math.rb"], test_command: [RbConfig.ruby, "checks.rb"])
      expect(results.size).to eq(6)
      expect(results).to all(have_attributes(killed: true))
      expect(File.binread(path)).to eq(code)
    end
  end

  it "distinguishes weak tests from a failing baseline with real processes" do
    in_project do
      path = write_source("math.rb", "VALUE = 1 + 2")
      config = { include: ["math.rb"], test_command: ruby_command('require_relative "math"; exit 0') }
      expect(Moots.run(config).map(&:killed)).to eq([false])
      expect { Moots.run(config.merge(test_command: ruby_command("exit 1"))) }
        .to raise_error(Moots::Error, /Baseline tests failed/)
      expect(File.binread(path)).to eq("VALUE = 1 + 2")
    end
  end

  it "restores a mutated source when a real command times out" do
    in_project do
      path = write_source("math.rb", "VALUE = 1 + 2")
      command = ruby_command('require_relative "math"; sleep 30 unless VALUE == 3')
      expect { Moots.run(include: ["math.rb"], test_command: command, timeout: 0.3) }
        .to raise_error(Moots::Error, /timed out/)
      expect(File.binread(path)).to eq("VALUE = 1 + 2")
    end
  end

  it "runs the packaged entry point with YAML and meaningful exit statuses" do
    in_project do
      path = write_source("math.rb", "VALUE = 1 + 2")
      write_source("check.rb", 'require_relative "math"; abort "wrong" unless VALUE == 3')
      File.write(".moots.yml", { "include" => ["math.rb"],
                                 "test_command" => [RbConfig.ruby, "check.rb"] }.to_yaml)
      stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-I", library, executable)
      expect(status.exitstatus).to eq(0), stderr
      expect(stdout).to include("1 mutations, 1 killed, 0 survived")
      expect(File.binread(path)).to eq("VALUE = 1 + 2")

      write_source("check.rb", "exit 0")
      stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-I", library, executable)
      expect(status.exitstatus).to eq(1), stderr
      expect(stdout).to include("SURVIVED", "1 mutations, 0 killed, 1 survived")

      write_source("check.rb", "exit 1")
      _stdout, stderr, status = Open3.capture3(RbConfig.ruby, "-I", library, executable)
      expect(status.exitstatus).to eq(2)
      expect(stderr).to include("Baseline tests failed")
    end
  end
end
