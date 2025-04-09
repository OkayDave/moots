# frozen_string_literal: true

require "ostruct"
require "tempfile"
require_relative "moots/version"
require_relative "moots/mutation"
require_relative "moots/mutation_generator"
require_relative "moots/test_runner"
require_relative "moots/test_result"

module Moots
  class Error < StandardError; end

  class << self
    def run(config)
      generator = MutationGenerator.new
      test_runner = TestRunner.new
      results = []

      files_to_test = find_files(config[:include], config[:exclude])

      files_to_test.each do |file|
        next unless File.exist?(file) && File.readable?(file)

        begin
          code = File.read(file)
          mutations = generator.generate_mutations(code)

          mutations.each do |mutation|
            # Apply mutation
            mutated_code = apply_mutation(code, mutation)
            File.write(file, mutated_code)

            # Run tests
            test_result = test_runner.run_tests(config[:test_command])

            # Record result - a mutation is "killed" if the tests fail
            results << OpenStruct.new(
              mutation: mutation,
              killed: test_result.success? == false
            )

            # Restore original code
            File.write(file, code)
          end
        rescue Errno::EACCES, Errno::ENOENT
          # Skip files we can't read or that don't exist
          next
        end
      end

      results
    end

    private

    def find_files(include_patterns, exclude_patterns)
      files = include_patterns.flat_map { |pattern| Dir[pattern] }
      exclude_files = exclude_patterns.flat_map { |pattern| Dir[pattern] }
      files - exclude_files
    end

    def apply_mutation(code, mutation)
      lines = code.lines
      line_index = mutation.line_number - 1
      lines[line_index] = lines[line_index].gsub(mutation.original_code, mutation.mutated_code)
      lines.join
    end
  end
end
