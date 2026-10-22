# frozen_string_literal: true

require "optparse"
require_relative "../moots"
require_relative "reporter"

module Moots
  # Command-line entry point. Survivors and empty runs have a failing exit status.
  class CLI
    def self.run(argv = ARGV, out: $stdout, err: $stderr)
      new(argv, out: out, err: err).run
    end

    def initialize(argv, out:, err:)
      @argv = argv
      @out = out
      @err = err
      @path = ".moots.yml"
      @explicit_path = false
      @format = "text"
      @overrides = {}
    end

    def run
      return 0 unless run_requested?

      @config_path = @path if @explicit_path || File.exist?(@path)
      config = @config_path ? Configuration.load(@config_path) : {}
      results = Moots.run(config.merge(@overrides)) { |event| reporter.call(event) }
      reporter.finish(results)
      return 1 if results.empty?

      results.all?(&:killed) ? 0 : 1
    rescue Error, OptionParser::ParseError, SystemCallError => e
      reporter.error(e.message)
      2
    rescue Interrupt
      reporter.error("Interrupted")
      130
    end

    private

    def reporter
      @reporter ||= Reporter.new(format: @format, out: @out, err: @err, config_path: @config_path)
    end

    def run_requested?
      parser = OptionParser.new do |options|
        options.banner = "Usage: moots [--config PATH] [--format text|json] [--mutation ID]"
        options.on("-c", "--config PATH", "Configuration file (default: .moots.yml)") do |value|
          @path = value
          @explicit_path = true
        end
        options.on("--format FORMAT", %w[text json], "Output format (default: text)") { |value| @format = value }
        options.on("--mutation ID", "Run one mutation by its reported ID") { |value| @overrides[:mutation] = value }
        options.on("-v", "--version", "Print version") do
          @out.puts(VERSION)
          return false
        end
        options.on("-h", "--help", "Show help") do
          @out.puts(options)
          return false
        end
      end
      remaining = parser.parse(@argv)
      raise Error, "Unexpected arguments: #{remaining.join(" ")}" unless remaining.empty?

      true
    end
  end
end
