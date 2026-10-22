# frozen_string_literal: true

RSpec.describe Moots do
  let(:runner) { instance_double(Moots::TestRunner) }
  let(:config) { { include: ["*.rb"], exclude: [], test_command: ["test-suite"], timeout: 2 } }

  before do
    allow(Moots::TestRunner).to receive(:new).and_return(runner)
    allow(runner).to receive(:run_tests).with(["test-suite"], timeout: 2).and_return(test_result(true))
  end

  it "checks the baseline and evaluates each mutation against the original source" do
    in_project do
      path = write_source("math.rb", "a + b; a * b")
      observed = []
      allow(runner).to receive(:run_tests) do
        observed << File.binread(path)
        test_result(observed.size == 1, "suite output")
      end
      results = described_class.run(config)
      expect(observed).to eq(["a + b; a * b", "a - b; a * b", "a + b; a / b"])
      expect(results.map(&:killed)).to eq([true, true])
      expect(results.map { |r| r.test_result.output }).to eq(["suite output", "suite output"])
      expect(results.map { |r| r.mutation.file_path }).to eq([path, path])
      expect(File.binread(path)).to eq("a + b; a * b")
    end
  end

  it "reports surviving mutations" do
    in_project do
      write_source
      expect(described_class.run(config).map(&:killed)).to eq([false])
    end
  end

  it "emits progress before commands and reports results only after restoring source" do
    in_project do
      path = write_source("math.rb", "a + b; a * b")
      events = []
      allow(runner).to receive(:run_tests) do
        expect(%i[baseline_started mutation_started]).to include(events.last.fetch(:type))
        test_result(true)
      end
      results = described_class.run(config) do |event|
        expect(File.binread(path)).to eq("a + b; a * b")
        events << event
      end
      expect(events.map { |event| event.fetch(:type) }).to eq(
        %i[baseline_started baseline_passed mutation_started mutation_finished mutation_started mutation_finished]
      )
      expect(events[2]).to include(index: 1, total: 2, mutation: results.first.mutation)
      expect(events[3]).to include(index: 1, total: 2, result: results.first)
      expect(events[4]).to include(index: 2, total: 2, mutation: results.last.mutation)
    end
  end

  %i[mutation_started mutation_finished].each do |stage|
    it "leaves original source intact if a progress callback raises at #{stage}" do
      in_project do
        path = write_source
        expect do
          described_class.run(config) { |event| raise "reporter failed" if event[:type] == stage }
        end.to raise_error("reporter failed")
        expect(File.binread(path)).to eq("a + b")
      end
    end
  end

  it "reruns only the selected mutation after a fresh baseline" do
    in_project do
      path = write_source("math.rb", "a + b; a * b")
      selected = Moots::MutationGenerator.new.generate_mutations(File.binread(path), file_path: path).last
      sources = []
      allow(runner).to receive(:run_tests) {
        sources << File.binread(path)
        test_result(true)
      }
      expect(described_class.run(config.merge(mutation: selected.id)).map do |result|
        result.mutation.id
      end).to eq([selected.id])
      expect(sources).to eq(["a + b; a * b", "a + b; a / b"])
      expect(File.binread(path)).to eq("a + b; a * b")
    end
  end

  it "rejects an unmatched mutation ID without changing source" do
    in_project do
      path = write_source
      expect(File).not_to receive(:binwrite)
      expect do
        described_class.run(config.merge(mutation: "0" * 16))
      end.to raise_error(Moots::Error, /No mutation matches/)
      expect(File.binread(path)).to eq("a + b")
    end
  end

  it "refuses to mutate when the baseline fails" do
    in_project do
      path = write_source
      allow(runner).to receive(:run_tests).and_return(test_result(false, "broken suite"))
      expect(File).not_to receive(:binwrite)
      expect { described_class.run(config) }.to raise_error(Moots::Error, /Baseline tests failed.*\nbroken suite/)
      expect(File.binread(path)).to eq("a + b")
      expect(runner).to have_received(:run_tests).once
    end
  end

  [RuntimeError, Moots::Error, Interrupt].each do |error|
    it "restores source bytes when execution raises #{error}" do
      in_project do
        code = "# é\r\na + b\r\n".b
        path = write_source("math.rb", code)
        calls = 0
        allow(runner).to receive(:run_tests) do
          calls += 1
          raise error, "interrupted" if calls == 2

          test_result(true)
        end
        expect { described_class.run(config) }.to raise_error(error, "interrupted")
        expect(File.binread(path)).to eq(code)
      end
    end
  end

  it "restores source after a partially failed write and surfaces the error" do
    in_project do
      path = write_source
      allow(File).to receive(:binwrite).and_call_original
      allow(File).to receive(:binwrite).with(path, "a - b") do
        File.binwrite(path, "partial")
        raise Errno::ENOSPC, path
      end
      expect { described_class.run(config) }.to raise_error(Errno::ENOSPC)
      expect(File.binread(path)).to eq("a + b")
    end
  end

  it "does not write stale source if applying a mutation fails" do
    in_project do
      write_source
      allow_any_instance_of(Moots::Mutation).to receive(:apply).and_raise(Moots::Error, "stale")
      expect(File).not_to receive(:binwrite)
      expect { described_class.run(config) }.to raise_error(Moots::Error, "stale")
    end
  end

  it "deduplicates include patterns, honors exclusions and skips directories" do
    in_project do
      write_source("lib/a.rb")
      write_source("lib/b.rb", "a * b")
      write_source("lib/skip.rb")
      write_source("app/c.rb", "a / b")
      FileUtils.mkdir_p("lib/directory.rb")
      results = described_class.run(config.merge(
                                      include: ["lib/*.rb", "./lib/a.rb", "app/*.rb"],
                                      exclude: ["./lib/skip.rb"]
                                    ))
      expect(results.map { |result| File.basename(result.mutation.file_path) }).to eq(%w[c.rb a.rb b.rb])
      expect(results.size).to eq(3)
      expect(runner).to have_received(:run_tests).exactly(4).times
    end
  end

  it "handles a missing glob and a source file with no operators" do
    in_project do
      write_source("constant.rb", "VALUE = 42")
      expect(described_class.run(config.merge(include: ["missing/*.rb", "*.rb"]))).to eq([])
      expect(runner).to have_received(:run_tests).once
    end
  end

  it "surfaces unreadable files instead of silently returning a misleading score" do
    in_project do
      path = write_source
      allow(File).to receive(:binread).with(path).and_raise(Errno::EACCES)
      expect { described_class.run(config) }.to raise_error(Errno::EACCES)
    end
  end

  it "rejects invalid source without changing it" do
    in_project do
      path = write_source("broken.rb", "def broken; a + b")
      expect { described_class.run(config) }.to raise_error(Moots::Error, /broken.rb/)
      expect(File.binread(path)).to eq("def broken; a + b")
    end
  end

  it "validates configuration before executing any command" do
    expect(runner).not_to receive(:run_tests)
    expect { described_class.run(timeout: 0) }.to raise_error(Moots::Error, /timeout/)
  end

  it "uses default patterns and commands when no configuration is supplied" do
    in_project do
      write_source("app/model.rb")
      allow(runner).to receive(:run_tests).with("bundle exec rspec", timeout: 60).and_return(test_result(true))
      expect(described_class.run.map(&:killed)).to eq([false])
      expect(runner).to have_received(:run_tests).with("bundle exec rspec", timeout: 60).twice
    end
  end
end
