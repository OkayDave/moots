# frozen_string_literal: true

require "timeout"

RSpec.describe "Isolated mutation execution" do
  it "runs baseline and mutants in one copy, preserving original bytes, artifacts, IDs and the parent cwd" do
    in_project do |root|
      source = "VALUE = 1 + 2"
      path = write_source("math.rb", source)
      check = write_source("check.rb", <<~RUBY)
        require_relative "math"
        abort "original changed" unless File.binread(#{path.dump}) == #{source.dump}
        File.open("artifact", "a") { |file| file.puts VALUE }
        puts JSON.generate(cwd: Dir.pwd, value: VALUE, history: File.readlines("artifact", chomp: true))
        exit(VALUE == 3 ? 0 : 1)
      RUBY
      config = { include: [path], test_command: [RbConfig.ruby, "-rjson", check] }
      events = []
      results = Moots.run(config) { |event| events << event.fetch(:type) }
      expect(events).to eq(%i[workspace_started baseline_started baseline_passed mutation_started mutation_finished])
      expect(results.map(&:killed)).to eq([true])
      result = results.first
      output = JSON.parse(result.test_result.output)
      expect(output).to include("value" => -1, "history" => ["3", "-1"])
      expect(output.fetch("cwd")).not_to eq(root)
      expect(File.exist?(output.fetch("cwd"))).to be(false)
      expect(result.mutation.file_path).to eq(path)
      expected = Moots::MutationGenerator.new.generate_mutations(source, file_path: path).first
      expect(result.mutation.id).to eq(expected.id)
      rerun = Moots.run(config.merge(mutation: expected.id))
      expect(rerun.map { |item| [item.mutation.id, item.killed] }).to eq([[expected.id, true]])
      expect(Dir.pwd).to eq(root)
      expect(File.binread(path)).to eq(source)
      expect(File.exist?("artifact")).to be(false)
    end
  end

  %i[baseline_started mutation_started mutation_finished].each do |stage|
    it "removes its workspace when interrupted at #{stage}" do
      in_project do
        path = write_source("math.rb", "VALUE = 1 + 2")
        directory = nil
        allow(Moots::TestRunner).to receive(:new).and_wrap_original do |original, **options|
          directory = options.fetch(:chdir)
          original.call(**options)
        end
        expect do
          Moots.run(include: ["math.rb"], test_command: ruby_command("exit 0")) do |event|
            raise Interrupt if event[:type] == stage
          end
        end.to raise_error(Interrupt)
        expect(File.exist?(directory)).to be(false)
        expect(File.binread(path)).to eq("VALUE = 1 + 2")
      end
    end
  end

  it "does not touch excluded artifacts, and can explicitly opt into in-place execution" do
    in_project do |root|
      write_source("math.rb", "VALUE = 1 + 2")
      write_source("tmp/fixture", "needed")
      command = ruby_command('puts Dir.pwd; abort "fixture missing" unless File.read("tmp/fixture") == "needed"')
      expect { Moots.run(include: ["math.rb"], test_command: command) }
        .to raise_error(Moots::Error, /Baseline tests failed/)
      results = Moots.run(include: ["math.rb"], test_command: command, workspace_exclude: [])
      expect(results.map(&:killed)).to eq([false])
      results = Moots.run(include: ["math.rb"], test_command: command, isolation: false)
      expect(results.first.test_result.output).to eq(root)
    end
  end

  it "keeps the original source intact even if the CLI is forcibly killed during a mutation",
     unless: Gem.win_platform? do
    executable = File.expand_path("../exe/moots", __dir__)
    library = File.expand_path("../lib", __dir__)
    # An outer scratch directory contains even the orphan left by SIGKILL.
    Dir.mktmpdir("moots-kill-spec-") do |scratch|
      scratch = File.realpath(scratch)
      root = File.join(scratch, "project")
      FileUtils.mkdir_p(root)
      marker = File.join(scratch, "ready.json")
      source = File.join(root, "math.rb")
      File.write(source, "VALUE = 1 + 2")
      File.write(File.join(root, "check.rb"), <<~RUBY)
        require "json"
        require_relative "math"
        exit 0 if VALUE == 3
        File.write(#{"#{marker}.part".dump}, JSON.generate(pid: Process.pid, directory: Dir.pwd))
        File.rename(#{"#{marker}.part".dump}, #{marker.dump})
        sleep 15
      RUBY
      File.write(File.join(root, ".moots.yml"), { "include" => ["math.rb"],
                                                  "test_command" => [RbConfig.ruby, "check.rb"] }.to_yaml)
      child_pid = nil
      command = [RbConfig.ruby, "-I", library, executable]
      Open3.popen3({ "TMPDIR" => scratch }, *command, chdir: root, pgroup: true) do |stdin, stdout, stderr, process|
        stdin.close
        begin
          Timeout.timeout(10) { sleep 0.01 until File.exist?(marker) }
          ready = JSON.parse(File.read(marker))
          child_pid = ready.fetch("pid")
          expect(File.binread(File.join(ready.fetch("directory"), "math.rb"))).to eq("VALUE = 1 - 2")
          expect(File.binread(source)).to eq("VALUE = 1 + 2")
          Process.kill("KILL", process.pid)
          expect(process.value).to be_signaled
          expect(File.binread(source)).to eq("VALUE = 1 + 2")
        ensure
          [child_pid, process.pid].compact.each do |pid|
            Process.kill("KILL", -pid)
          rescue Errno::ESRCH
            nil
          end
        end
        expect(stdout.read).to include("[1/1] Testing")
        expect(stderr.read).to eq("")
      end
    end
  end
end
