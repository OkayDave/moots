# frozen_string_literal: true

require "timeout"

RSpec.describe "Parallel mutation execution" do
  around { |example| Timeout.timeout(12) { example.run } }

  it "overlaps isolated mutants, runs one baseline, preserves input order and rebases inherited paths twice" do
    Dir.mktmpdir("moots-coordination-") do |control|
      in_project do |root|
        source = "VALUES = [1 + 2, 3 * 4]"
        path = write_source("math.rb", source)
        write_source("support/location.rb", "LOCATION = __dir__")
        allow(ENV).to receive(:key?).and_call_original
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:key?).with("RUBYLIB").and_return(true)
        allow(ENV).to receive(:fetch).with("RUBYLIB").and_return("#{root}/support")
        check = write_source("check.rb", <<~RUBY)
          require "json"
          require "location"
          require_relative "math"
          control = #{control.dump}
          abort "original changed" unless File.binread(#{path.dump}) == #{source.dump}
          if VALUES == [3, 12]
            File.open(File.join(control, "baselines"), "a") { |f| f.puts Dir.pwd }
            File.write("artifact", "baseline\n")
            exit 0
          end
          name = VALUES.first == -1 ? "first" : "second"
          File.write(File.join(control, name), Dir.pwd)
          sleep 0.01 until File.exist?(File.join(control, "first")) && File.exist?(File.join(control, "second"))
          sleep 0.01 until File.exist?(File.join(control, "release")) if name == "first"
          File.open("artifact", "a") { |f| f.puts name }
          puts JSON.generate(cwd: Dir.pwd, values: VALUES, location: LOCATION, artifact: File.read("artifact"))
          exit(name == "first" ? 1 : 0)
        RUBY
        finished = []
        caller = Thread.current
        results = Moots.run(include: ["math.rb"], test_command: [RbConfig.ruby, check], jobs: 2) do |event|
          expect(Thread.current).to eq(caller)
          next unless event[:type] == :mutation_finished

          finished << event.fetch(:index)
          File.write(File.join(control, "release"), "") if event[:index] == 2
        end
        expect(finished).to eq([2, 1])
        expect(results.map(&:killed)).to eq([true, false])
        expected = Moots::MutationGenerator.new.generate_mutations(source, file_path: path).map(&:id)
        expect(results.map { |item| item.mutation.id }).to eq(expected)
        outputs = results.map { |item| JSON.parse(item.test_result.output) }
        expect(outputs.map { |item| item.fetch("values") }).to eq([[-1, 12], [3, 0]])
        expect(outputs.map { |item| item.fetch("artifact") }).to eq(%W[baseline\nfirst\n baseline\nsecond\n])
        expect(outputs.map { |item| item.fetch("cwd") }.uniq.size).to eq(2)
        outputs.each do |item|
          expect(item.fetch("location")).to eq("#{item.fetch("cwd")}/support")
          expect(File.exist?(item.fetch("cwd"))).to be(false)
        end
        baselines = File.readlines(File.join(control, "baselines"), chomp: true)
        expect(baselines.size).to eq(1)
        expect(File.exist?(baselines.first)).to be(false)
        expect(File.binread(path)).to eq(source)
        expect(File.exist?("artifact")).to be(false)
      end
    end
  end

  it "caps workers at the mutation count and avoids a pool for single or empty selections" do
    in_project do
      path = write_source("math.rb", "VALUES = [1 + 2, 3 * 4]")
      config = { include: ["math.rb"], test_command: ruby_command("exit 0"), jobs: 8 }
      expect_any_instance_of(Moots::Workspace).to receive(:with_workers).with(2).and_call_original
      results = Moots.run(config)
      expect(results.map(&:killed)).to eq([false, false])
      expect(Moots::WorkerPool).not_to receive(:new)
      expect(Moots.run(config.merge(mutation: results.last.mutation.id)).map { |item| item.mutation.id })
        .to eq([results.last.mutation.id])
      File.write(path, "VALUE = 42")
      expect(Moots.run(config)).to eq([])
    end
  end

  it "terminates other test processes and removes their copies on an operational failure" do
    Dir.mktmpdir("moots-cancellation-") do |control|
      in_project do
        source = "VALUES = [1 + 2, 3 * 4]"
        path = write_source("math.rb", source)
        write_source("check.rb", <<~RUBY)
          require "json"
          require_relative "math"
          exit 0 if VALUES == [3, 12]
          marker = #{File.join(control, "running").dump}
          if VALUES.first == -1
            sleep 0.01 until File.exist?(marker)
            exit 127
          end
          File.write("\#{marker}.part", JSON.generate(pid: Process.pid, directory: Dir.pwd))
          File.rename("\#{marker}.part", marker)
          sleep 30
        RUBY
        expect { Moots.run(include: ["math.rb"], test_command: [RbConfig.ruby, "check.rb"], jobs: 2) }
          .to raise_error(Moots::Error, /could not execute \(exit 127\)/)
        running = JSON.parse(File.read(File.join(control, "running")))
        expect { Process.kill(0, running.fetch("pid")) }.to raise_error(Errno::ESRCH)
        expect(File.exist?(running.fetch("directory"))).to be(false)
        expect(File.read(path)).to eq(source)
      end
    end
  end
end
