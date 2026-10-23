# frozen_string_literal: true

RSpec.describe Moots::TestRunner do
  subject(:runner) { described_class.new }

  it "returns success with empty output" do
    result = runner.run_tests(ruby_command("exit 0"))
    expect(result).to be_success
    expect(result.output).to eq("")
  end

  it "runs in the requested directory and environment without changing the parent" do
    original_directory = Dir.pwd
    original_environment = ENV.to_h
    in_project do |directory|
      result = described_class.new(chdir: directory, env: { "MOOTS_CHILD_ONLY" => "child" })
                              .run_tests(ruby_command('puts Dir.pwd; puts ENV.fetch("MOOTS_CHILD_ONLY")'))
      expect(result.output.lines.map(&:chomp)).to eq([directory, "child"])
      expect(Dir.pwd).to eq(directory)
    end
    expect(Dir.pwd).to eq(original_directory)
    expect(ENV.to_h).to eq(original_environment)
  end

  it "captures failure and stderr" do
    result = runner.run_tests(ruby_command('warn "failure"; exit 1'))
    expect(result).not_to be_success
    expect(result.output).to eq("failure")
  end

  it "combines stdout and stderr while preserving interior newlines" do
    result = runner.run_tests(ruby_command('puts "first\n\nlast"; warn "error"'))
    expect(result).to be_success
    expect(result.output).to eq("first\n\nlast\n\nerror")
  end

  it "drains large stdout and stderr without deadlocking" do
    result = runner.run_tests(ruby_command('$stdout.write("a" * 100_000); $stderr.write("b" * 100_000)'))
    expect(result.output).to eq("#{"a" * 100_000}\n#{"b" * 100_000}")
  end

  it "closes stdin so readers see EOF" do
    expect(runner.run_tests(ruby_command("exit(STDIN.read.empty? ? 0 : 1)"))).to be_success
  end

  it "supports command strings" do
    result = runner.run_tests(%("#{RbConfig.ruby}" -e "puts 123"))
    expect(result.output).to eq("123")
  end

  it "passes argument arrays literally, including spaces and shell metacharacters" do
    result = runner.run_tests([RbConfig.ruby, "-e", "puts ARGV", "a b; &&"])
    expect(result.output).to eq("a b; &&")
  end

  it "reports missing executables" do
    expect { runner.run_tests(["moots-nonexistent-command-98217"]) }
      .to raise_error(Moots::Error, /Cannot execute/)
  end

  [126, 127].each do |status|
    it "does not count shell execution failure #{status} as a killed mutation" do
      expect { runner.run_tests(ruby_command("exit #{status}")) }
        .to raise_error(Moots::Error, /could not execute \(exit #{status}\)/)
    end
  end

  it "terminates commands that exceed their deadline" do
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    expect { runner.run_tests(ruby_command("sleep 30"), timeout: 0.2) }
      .to raise_error(Moots::Error, /timed out after 0.2 seconds/)
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 5
  end

  it "reports signal termination", unless: Gem.win_platform? do
    expect { runner.run_tests(ruby_command('Process.kill("KILL", Process.pid)')) }
      .to raise_error(Moots::Error, /terminated by signal/)
  end

  it "kills descendants that keep the output pipe open", unless: Gem.win_platform? do
    command = ruby_command("fork { sleep 30 }; exit! 0")
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    expect { runner.run_tests(command, timeout: 0.2) }.to raise_error(Moots::Error, /timed out/)
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 5
  end

  context "with a controlled process" do
    let(:input) { StringIO.new }
    let(:output) { StringIO.new("") }
    let(:error_output) { StringIO.new("") }
    let(:status) { instance_double(Process::Status, success?: true, signaled?: false, exitstatus: 0) }
    let(:process) { double("process", pid: 456_789, value: status) }

    before do
      allow(Open3).to receive(:popen3).and_yield(input, output, error_output, process)
    end

    it "reports a signaled process and cleans up its group on every host platform" do
      allow(Gem).to receive(:win_platform?).and_return(false)
      allow(status).to receive_messages(signaled?: true, termsig: 15)
      expect(Process).to receive(:kill).with("KILL", -456_789).and_raise(Errno::ESRCH)
      expect { runner.run_tests("suite") }.to raise_error(Moots::Error, /terminated by signal 15/)
    end

    it "creates a Windows process group and kills the tree on timeout" do
      allow(Gem).to receive(:win_platform?).and_return(true)
      allow(process).to receive(:value).and_raise(Timeout::Error)
      expect(runner).to receive(:system)
        .with("taskkill", "/PID", "456789", "/T", "/F", out: File::NULL, err: File::NULL).and_return(true)
      expect { runner.run_tests("suite", timeout: 1) }.to raise_error(Moots::Error, /timed out/)
      expect(Open3).to have_received(:popen3).with({}, "suite", chdir: Dir.pwd, new_pgroup: true)
    end

    it "tolerates a process that exits just before POSIX cleanup" do
      allow(Gem).to receive(:win_platform?).and_return(false)
      allow(process).to receive(:value).and_raise(Timeout::Error)
      expect(Process).to receive(:kill).with("KILL", -456_789).and_raise(Errno::ESRCH)
      expect { runner.run_tests("suite") }.to raise_error(Moots::Error, /timed out/)
      expect(Open3).to have_received(:popen3).with({}, "suite", chdir: Dir.pwd, pgroup: true)
    end

    it "terminates a running command on interruption" do
      allow(Gem).to receive(:win_platform?).and_return(false)
      allow(process).to receive(:value).and_raise(Interrupt)
      expect(Process).to receive(:kill).with("KILL", -456_789)
      expect { runner.run_tests("suite") }.to raise_error(Interrupt)
    end
  end
end
