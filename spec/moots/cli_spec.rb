# frozen_string_literal: true

RSpec.describe Moots::CLI do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }
  let(:mutation) do
    Moots::Mutation.new(original_code: "a + b", mutated_code: "a - b",
                        line_number: 3, file_path: "math.rb", start_offset: 0)
  end

  def invoke(*args)
    described_class.run(args, out: out, err: err)
  end

  def result(killed)
    Moots::Result.new(mutation: mutation, killed: killed, test_result: test_result(!killed))
  end

  ["-h", "--help"].each do |flag|
    it "prints help with #{flag} without running tests" do
      expect(Moots).not_to receive(:run)
      expect(invoke(flag)).to eq(0)
      expect(out.string).to include("Usage: moots", "--config", "--version")
      expect(err.string).to eq("")
    end
  end

  ["-v", "--version"].each do |flag|
    it "prints the version with #{flag}" do
      expect(Moots).not_to receive(:run)
      expect(invoke(flag)).to eq(0)
      expect(out.string).to eq("#{Moots::VERSION}\n")
    end
  end

  it "uses defaults when no configuration file exists and succeeds for all killed" do
    in_project do
      killed = result(true)
      expect(Moots).to receive(:run).with({}).and_yield(type: :mutation_finished, result: killed).and_return([killed])
      expect(invoke).to eq(0)
      expect(out.string).to eq("KILLED #{mutation.id} math.rb:3\n1 mutations, 1 killed, 0 survived\n")
    end
  end

  it "loads the default configuration when present" do
    in_project do
      File.write(".moots.yml", "include: [src/*.rb]")
      expect(Moots).to receive(:run).with(hash_including(include: ["src/*.rb"])).and_return([result(true)])
      expect(invoke).to eq(0)
    end
  end

  ["-c", "--config"].each do |flag|
    it "uses the explicit config path with #{flag}" do
      in_project do
        File.write("custom.yml", "timeout: 5")
        expect(Moots).to receive(:run).with(hash_including(timeout: 5)).and_return([result(true)])
        expect(invoke(flag, "custom.yml")).to eq(0)
      end
    end
  end

  it "fails and displays exact expressions for survivors and mixed results" do
    in_project do
      killed = result(true)
      survived = result(false)
      allow(Moots).to receive(:run).and_yield(type: :mutation_finished, result: killed)
                                   .and_yield(type: :mutation_finished, result: survived).and_return([killed, survived])
      expect(invoke).to eq(1)
      expect(out.string).to include("SURVIVED #{mutation.id} math.rb:3", "  - a + b\n  + a - b\n",
                                    "2 mutations, 1 killed, 1 survived")
    end
  end

  it "does not report a vacuous pass for zero mutations" do
    in_project do
      allow(Moots).to receive(:run).and_return([])
      expect(invoke).to eq(1)
      expect(out.string).to eq("0 mutations, 0 killed, 0 survived\n")
    end
  end

  [["--unknown"], ["--config"], ["unexpected"], ["--format", "xml"], ["--mutation"]].each do |args|
    it "rejects invalid arguments #{args.inspect}" do
      expect(Moots).not_to receive(:run)
      expect(invoke(*args)).to eq(2)
      expect(err.string).to start_with("moots: ")
    end
  end

  it "reports a missing explicit configuration instead of falling back to defaults" do
    in_project do
      expect(Moots).not_to receive(:run)
      expect(invoke("--config", "missing.yml")).to eq(2)
      expect(err.string).to include("Cannot load configuration missing.yml")
    end
  end

  [Moots::Error.new("baseline failed"), Errno::EACCES.new("source.rb")].each do |error|
    it "reports operational error #{error.class}" do
      in_project do
        allow(Moots).to receive(:run).and_raise(error)
        expect(invoke).to eq(2)
        expect(err.string).to include(error.message)
      end
    end
  end

  it "uses the CLI mutation selection in preference to YAML" do
    in_project do
      File.write(".moots.yml", "mutation: '1111111111111111'")
      expect(Moots).to receive(:run).with(hash_including(mutation: "2222222222222222")).and_return([result(true)])
      expect(invoke("--mutation", "2222222222222222")).to eq(0)
    end
  end

  ["-j", "--jobs"].each do |flag|
    it "overrides YAML workers with #{flag}" do
      in_project do
        File.write(".moots.yml", "jobs: 2")
        expect(Moots).to receive(:run).with(hash_including(jobs: 3)).and_return([result(true)])
        expect(invoke(flag, "3")).to eq(0)
      end
    end
  end

  [["--jobs"], ["--jobs", "many"], ["--jobs", "1.5"]].each do |arguments|
    it "rejects invalid worker arguments #{arguments.inspect}" do
      expect(Moots).not_to receive(:run)
      expect(invoke(*arguments)).to eq(2)
      expect(err.string).to include("moots:")
    end
  end

  it "returns a complete JSON report and failing exit status for an empty run" do
    in_project do
      allow(Moots).to receive(:run).and_return([])
      expect(invoke("--format", "json")).to eq(1)
      expect(JSON.parse(out.string)).to eq(
        "schema_version" => 1, "status" => "completed", "results" => [],
        "summary" => { "mutations" => 0, "killed" => 0, "survived" => 0 }
      )
    end
  end

  it "reports partial results as an error when execution fails after a completed mutation" do
    in_project do
      allow(Moots).to receive(:run) do |&progress|
        progress.call(type: :mutation_finished, result: result(true))
        raise Moots::Error, "Test command timed out"
      end
      expect(invoke("--format", "json")).to eq(2)
      report = JSON.parse(out.string)
      expect(report).to include("status" => "error", "error" => "Test command timed out")
      expect(report.fetch("summary")).to eq("mutations" => 1, "killed" => 1, "survived" => 0)
      expect(report.fetch("results").map { |item| item.fetch("status") }).to eq(["killed"])
      expect(err.string).to include("KILLED", "moots: Test command timed out")
    end
  end

  it "returns a structured error for malformed selection before running tests" do
    in_project do
      expect(Moots::TestRunner).not_to receive(:new)
      expect(invoke("--format", "json", "--mutation", "bad")).to eq(2)
      expect(JSON.parse(out.string)).to include("status" => "error", "results" => [])
      expect(err.string).to include("mutation must be")
    end
  end

  it "returns a structured parse error after JSON format is selected" do
    expect(invoke("--format", "json", "--unknown")).to eq(2)
    expect(JSON.parse(out.string)).to include("status" => "error", "results" => [])
  end

  it "reports interruptions without declaring a completed run" do
    in_project do
      allow(Moots).to receive(:run).and_raise(Interrupt)
      expect(invoke("--format", "json")).to eq(130)
      expect(JSON.parse(out.string)).to include("status" => "error", "error" => "Interrupted", "results" => [])
    end
  end
end
