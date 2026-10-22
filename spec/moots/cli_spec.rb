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
      expect(Moots).to receive(:run).with({}).and_return([result(true)])
      expect(invoke).to eq(0)
      expect(out.string).to eq("KILLED math.rb:3\n1 mutations, 1 killed, 0 survived\n")
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
      allow(Moots).to receive(:run).and_return([result(true), result(false)])
      expect(invoke).to eq(1)
      expect(out.string).to include("SURVIVED math.rb:3", '"a + b" -> "a - b"',
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

  [["--unknown"], ["--config"], ["unexpected"]].each do |args|
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
end
