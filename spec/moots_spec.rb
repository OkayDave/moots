# frozen_string_literal: true

RSpec.describe Moots do
  let(:config) do
    {
      include: ["lib/**/*.rb"],
      exclude: [],
      test_command: "bundle exec rspec"
    }
  end

  describe ".run" do
    let(:generator) { instance_double(Moots::MutationGenerator) }
    let(:test_runner) { instance_double(Moots::TestRunner) }
    let(:mutation) do
      instance_double(
        Moots::Mutation,
        original_code: "a + b",
        mutated_code: "a - b",
        line_number: 1,
        file_path: "lib/example.rb"
      )
    end

    before do
      allow(Moots::MutationGenerator).to receive(:new).and_return(generator)
      allow(Moots::TestRunner).to receive(:new).and_return(test_runner)
      allow(generator).to receive(:generate_mutations).and_return([mutation])
    end

    context "when tests fail for a mutation" do
      before do
        allow(test_runner).to receive(:run_tests).and_return(
          instance_double(Moots::TestResult, success?: false, output: "Test failure")
        )
      end

      it "marks the mutation as killed" do
        results = described_class.run(config)

        expect(results.first).to have_attributes(
          mutation: mutation,
          killed: true
        )
      end
    end

    context "when tests pass for a mutation" do
      before do
        allow(test_runner).to receive(:run_tests).and_return(
          instance_double(Moots::TestResult, success?: true, output: "")
        )
      end

      it "marks the mutation as survived" do
        results = described_class.run(config)

        expect(results.first).to have_attributes(
          mutation: mutation,
          killed: false
        )
      end
    end

    context "with file handling" do
      let(:temp_file) { Tempfile.new(["test", ".rb"]) }
      let(:code) { "def add(a, b); a + b; end" }

      before do
        temp_file.write(code)
        temp_file.close
        allow(Dir).to receive(:[]).with("lib/**/*.rb").and_return([temp_file.path])
      end

      after do
        temp_file.unlink
      end

      it "restores original code after mutation" do
        allow(test_runner).to receive(:run_tests).and_return(
          instance_double(Moots::TestResult, success?: true, output: "")
        )

        described_class.run(config)

        expect(File.read(temp_file.path)).to eq(code)
      end
    end

    context "with configuration" do
      it "handles multiple include patterns" do
        config[:include] = ["lib/**/*.rb", "app/**/*.rb"]
        allow(Dir).to receive(:[]).with("lib/**/*.rb").and_return(["lib/file1.rb"])
        allow(Dir).to receive(:[]).with("app/**/*.rb").and_return(["app/file2.rb"])

        results = described_class.run(config)

        expect(results).to be_an(Array)
      end

      it "handles exclude patterns" do
        config[:exclude] = ["lib/vendor/**/*.rb"]
        allow(Dir).to receive(:[]).with("lib/**/*.rb").and_return(["lib/file.rb", "lib/vendor/ignored.rb"])
        allow(Dir).to receive(:[]).with("lib/vendor/**/*.rb").and_return(["lib/vendor/ignored.rb"])

        results = described_class.run(config)

        expect(results).to be_an(Array)
      end
    end

    context "with error handling" do
      it "handles non-existent files gracefully" do
        allow(Dir).to receive(:[]).with("lib/**/*.rb").and_return(["nonexistent.rb"])

        results = described_class.run(config)

        expect(results).to be_an(Array)
        expect(results).to be_empty
      end

      it "handles unreadable files gracefully" do
        temp_file = Tempfile.new(["test", ".rb"])
        temp_file.close
        File.chmod(0, temp_file.path)
        allow(Dir).to receive(:[]).with("lib/**/*.rb").and_return([temp_file.path])

        results = described_class.run(config)

        expect(results).to be_an(Array)
        expect(results).to be_empty

        temp_file.unlink
      end
    end
  end
end
