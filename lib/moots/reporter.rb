# frozen_string_literal: true

require "json"

module Moots
  # Stream progress independently of the final, versioned machine-readable report.
  class Reporter
    def initialize(format:, out:, err:, config_path: nil, root: Dir.pwd)
      @format = format
      @out = out
      @err = err
      @progress = format == "json" ? err : out
      @config_path = config_path
      @root = root
      @results = []
    end

    def call(event)
      case event.fetch(:type)
      when :workspace_started
        @progress.puts("Preparing isolated working copy...")
      when :baseline_started
        @progress.puts("Running baseline tests...")
      when :baseline_passed
        @progress.puts("Baseline passed.")
      when :mutation_started
        @progress.puts("[#{event.fetch(:index)}/#{event.fetch(:total)}] Testing #{location(event.fetch(:mutation))}")
      when :mutation_finished
        result = event.fetch(:result)
        @results[event.fetch(:index, @results.size)] = result
        @progress.puts("#{result.killed ? "KILLED" : "SURVIVED"} #{location(result.mutation)}")
        survivor(result.mutation) unless result.killed
      else
        raise ArgumentError, "Unknown progress event: #{event[:type]}"
      end
      @progress.flush
    end

    def finish(results)
      @results = results
      if @format == "json"
        @out.puts(JSON.generate(document("completed")))
      else
        counts = summary
        @out.puts("#{counts[:mutations]} mutations, #{counts[:killed]} killed, #{counts[:survived]} survived")
      end
      @out.flush
    end

    def error(message)
      @err.puts("moots: #{text(message)}")
      @err.flush
      return unless @format == "json"

      @out.puts(JSON.generate(document("error").merge(error: text(message))))
      @out.flush
    end

    private

    def text(value)
      value.dup.force_encoding(Encoding::UTF_8).scrub
    end

    def location(mutation)
      "#{mutation.id(root: @root)} #{text(mutation.relative_path(root: @root))}:#{mutation.line_number}"
    end

    def rerun(mutation)
      command = %w[bundle exec moots]
      command.push("--config", @config_path) if @config_path
      command + ["--mutation", mutation.id(root: @root)]
    end

    def survivor(mutation)
      @progress.puts("  Expression diff:")
      text(mutation.original_code).each_line { |line| @progress.puts("  - #{line.chomp}") }
      text(mutation.mutated_code).each_line { |line| @progress.puts("  + #{line.chomp}") }
      @progress.puts("  Rerun argv: #{JSON.generate(rerun(mutation))}")
    end

    def summary
      completed = @results.compact
      killed = completed.count(&:killed)
      { mutations: completed.size, killed: killed, survived: completed.size - killed }
    end

    def document(status)
      serialized = @results.compact.map { |result| serialize(result) }
      { schema_version: 1, status: status, summary: summary, results: serialized }
    end

    def serialize(result)
      mutation = result.mutation
      {
        id: mutation.id(root: @root), file: text(mutation.relative_path(root: @root)),
        line: mutation.line_number, start_offset: mutation.start_offset,
        original: text(mutation.original_code), mutated: text(mutation.mutated_code),
        status: result.killed ? "killed" : "survived", test_output: text(result.test_result.output),
        rerun: rerun(mutation)
      }
    end
  end
end
