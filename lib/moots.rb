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
    def run(options = {}, &progress)
      config = Configuration.new(options).to_h
      runner = TestRunner.new
      verify_baseline(runner, config, progress)
      targets = mutation_targets(config)
      targets.each_with_index.map do |(code, mutation), index|
        position = { index: index + 1, total: targets.size }
        emit(progress, :mutation_started, **position, mutation: mutation)
        test_result = test_mutation(mutation.file_path, code, mutation, runner, config)
        result = Result.new(mutation: mutation, killed: !test_result.success?, test_result: test_result)
        emit(progress, :mutation_finished, **position, result: result)
        result
      end
    end

    private

    def emit(progress, type, **payload)
      progress&.call(type: type, **payload)
    end

    def verify_baseline(runner, config, progress)
      emit(progress, :baseline_started)
      baseline = runner.run_tests(config[:test_command], timeout: config[:timeout])
      raise Error, "Baseline tests failed; no mutations applied.\n#{baseline.output}" unless baseline.success?

      emit(progress, :baseline_passed)
    end

    def mutation_targets(config)
      generator = MutationGenerator.new
      targets = find_files(config).flat_map do |file|
        code = File.binread(file)
        generator.generate_mutations(code, file_path: file).map { |mutation| [code, mutation] }
      end
      return targets unless config[:mutation]

      selected = targets.select { |_code, mutation| mutation.id == config[:mutation] }
      if selected.empty?
        raise Error,
              "No mutation matches #{config[:mutation]}; source or configuration may have changed."
      end

      selected
    end

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
