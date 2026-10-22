# frozen_string_literal: true

require_relative "moots/version"
require_relative "moots/configuration"
require_relative "moots/mutation_generator"
require_relative "moots/test_runner"

# Sequential mutation testing for Ruby projects.
module Moots
  Result = Struct.new(:mutation, :killed, :test_result, keyword_init: true)

  class << self
    # Verify the baseline, then run the suite once per mutation. Always restore bytes.
    def run(options = {})
      config = Configuration.new(options).to_h
      runner = TestRunner.new
      baseline = runner.run_tests(config[:test_command], timeout: config[:timeout])
      raise Error, "Baseline tests failed; no mutations applied.\n#{baseline.output}" unless baseline.success?

      generator = MutationGenerator.new
      find_files(config).flat_map do |file|
        code = File.binread(file)
        generator.generate_mutations(code, file_path: file).map do |mutation|
          test_result = test_mutation(file, code, mutation, runner, config)
          Result.new(mutation: mutation, killed: !test_result.success?, test_result: test_result)
        end
      end
    end

    private

    def find_files(config)
      included = config[:include].flat_map { |pattern| Dir[pattern] }
      excluded = config[:exclude].flat_map { |pattern| Dir[pattern] }.map { |path| File.expand_path(path) }
      included.map { |path| File.expand_path(path) }.uniq.sort.reject do |path|
        excluded.include?(path) || !File.file?(path)
      end
    end

    def test_mutation(file, code, mutation, runner, config)
      mutated_code = mutation.apply(code)
      begin
        File.binwrite(file, mutated_code)
        runner.run_tests(config[:test_command], timeout: config[:timeout])
      ensure
        File.binwrite(file, code)
      end
    end
  end
end
