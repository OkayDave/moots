# frozen_string_literal: true

RSpec.describe "Comparison mutation acceptance" do
  around { |example| Timeout.timeout(20) { example.run } }

  let(:fixture) { File.expand_path("fixtures/comparisons", __dir__) }
  let(:expected_mutations) do
    [
      ["actual == expected", "actual != expected", 6],
      ["actual != expected", "actual == expected", 10],
      ["value > boundary", "value >= boundary", 14],
      ["value >= boundary", "value > boundary", 18],
      ["value < boundary", "value <= boundary", 22],
      ["value <= boundary", "value < boundary", 26]
    ]
  end

  %w[rspec minitest].product(%w[strong weak], [1, 2]).each do |framework, strength, jobs|
    it "reports expected kills and survivors for #{framework}'s #{strength} suite with #{jobs} workers" do
      in_project do
        FileUtils.cp_r(Dir[File.join(fixture, "*")], ".")
        original_files = Dir["**/*"].select { |path| File.file?(path) }.to_h do |path|
          [path, File.binread(path)]
        end
        results = Moots.run(
          include: ["lib/**/*.rb"],
          jobs: jobs,
          test_command: [RbConfig.ruby, "run_#{framework}.rb", strength]
        )

        expect(results.map do |result|
          mutation = result.mutation
          [mutation.original_code, mutation.mutated_code, mutation.line_number]
        end).to eq(expected_mutations)
        expected_kills = strength == "strong" ? [true] * 6 : [true, true, false, false, false, false]
        expect(results.map(&:killed)).to eq(expected_kills)
        results.each do |result|
          expect(result.mutation.file_path).to eq(File.expand_path("lib/comparison_rules.rb"))
          expect(result.test_result.success?).to be(!result.killed)
          if framework == "rspec"
            summary = result.killed ? "6 examples, 1 failure" : "6 examples, 0 failures"
            expect(result.test_result.output).to include(summary)
            expect(result.test_result.output).to include("Failure/Error") if result.killed
          else
            expect(result.test_result.output).to include("6 runs", "0 errors")
            expect(result.test_result.output).to include(result.killed ? "1 failures" : "0 failures")
          end
        end
        expect(original_files.keys.to_h { |path| [path, File.binread(path)] }).to eq(original_files)
      end
    end
  end
end
