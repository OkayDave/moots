# frozen_string_literal: true

require_relative "moots/version"
require_relative "moots/configuration"
require_relative "moots/mutation_generator"
require_relative "moots/test_runner"
require_relative "moots/workspace"
require_relative "moots/worker_pool"

# Mutation testing for Ruby projects with isolated test processes.
module Moots
  Result = Struct.new(:mutation, :killed, :test_result, keyword_init: true)

  class << self
    # Verify the baseline, then run each mutation in a disposable project snapshot.
    def run(options = {}, &progress)
      config = Configuration.new(options).to_h
      emit(progress, :workspace_started) if config[:isolation]
      Workspace.new(isolation: config[:isolation], workspace_exclude: config[:workspace_exclude]).open do |workspace|
        execute(config.merge(test_command: workspace.command(config[:test_command])), workspace, progress)
      end
    end

    private

    def execute(config, workspace, progress)
      runner = TestRunner.new(chdir: workspace.directory, env: workspace.environment)
      verify_baseline(runner, config, progress)
      targets = mutation_targets(config, workspace)
      return run_parallel(targets, config, workspace, progress) if config[:jobs] > 1 && targets.size > 1

      targets.each_with_index.map do |(file, code, mutation), index|
        position = { index: index + 1, total: targets.size }
        emit(progress, :mutation_started, **position, mutation: mutation)
        test_result = test_mutation(file, code, mutation, runner, config)
        result = Result.new(mutation: mutation, killed: !test_result.success?, test_result: test_result)
        emit(progress, :mutation_finished, **position, result: result)
        result
      end
    end

    def run_parallel(targets, config, workspace, progress)
      workspace.with_workers([config[:jobs], targets.size].min) do |copies|
        workers = copies.map do |copy|
          runner = TestRunner.new(chdir: copy.directory, env: copy.environment(workspace.environment))
          [copy, runner, config.merge(test_command: copy.command(config[:test_command]))]
        end
        before = lambda do |target, index|
          emit(progress, :mutation_started, index: index + 1, total: targets.size, mutation: target.last)
        end
        after = lambda do |result, index|
          emit(progress, :mutation_finished, index: index + 1, total: targets.size, result: result)
        end
        WorkerPool.new(workers, before: before, after: after).map(targets) do |(copy, runner, options), target|
          file, code, mutation = target
          test_result = test_mutation(copy.command([file]).first, code, mutation, runner, options)
          Result.new(mutation: mutation, killed: !test_result.success?, test_result: test_result)
        end
      end
    end

    def emit(progress, type, **payload)
      progress&.call(type: type, **payload)
    end

    def verify_baseline(runner, config, progress)
      emit(progress, :baseline_started)
      baseline = runner.run_tests(config[:test_command], timeout: config[:timeout])
      raise Error, "Baseline tests failed; no mutations applied.\n#{baseline.output}" unless baseline.success?

      emit(progress, :baseline_passed)
    end

    def mutation_targets(config, workspace)
      generator = MutationGenerator.new
      targets = find_files(config, workspace).flat_map do |file|
        code = File.binread(file)
        generator.generate_mutations(code, file_path: workspace.original_path(file)).map do |mutation|
          [file, code, mutation]
        end
      end
      return targets unless config[:mutation]

      selected = targets.select { |_file, _code, mutation| mutation.id == config[:mutation] }
      if selected.empty?
        raise Error,
              "No mutation matches #{config[:mutation]}; source or configuration may have changed."
      end

      selected
    end

    def find_files(config, workspace)
      included = workspace.files(config[:include])
      excluded = workspace.files(config[:exclude])
      included.reject do |path|
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
