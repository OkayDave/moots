# frozen_string_literal: true

require "optparse"
require_relative "../moots"

module Moots
  # Command-line entry point. Survivors and empty runs have a failing exit status.
  class CLI
    def self.run(argv = ARGV, out: $stdout, err: $stderr)
      path = ".moots.yml"
      explicit_path = false
      parser = OptionParser.new do |options|
        options.banner = "Usage: moots [--config PATH]"
        options.on("-c", "--config PATH", "Configuration file (default: .moots.yml)") do |value|
          path = value
          explicit_path = true
        end
        options.on("-v", "--version", "Print version") do
          out.puts(VERSION)
          return 0
        end
        options.on("-h", "--help", "Show help") do
          out.puts(options)
          return 0
        end
      end
      remaining = parser.parse(argv)
      raise Error, "Unexpected arguments: #{remaining.join(" ")}" unless remaining.empty?

      config = explicit_path || File.exist?(path) ? Configuration.load(path) : {}
      results = Moots.run(config)
      report(results, out)
      return 1 if results.empty?

      results.all?(&:killed) ? 0 : 1
    rescue Error, OptionParser::ParseError, SystemCallError => e
      err.puts("moots: #{e.message}")
      2
    end

    def self.report(results, out)
      results.each do |result|
        mutation = result.mutation
        out.puts("#{result.killed ? "KILLED" : "SURVIVED"} #{mutation.file_path}:#{mutation.line_number}")
        next if result.killed

        out.puts("  #{mutation.original_code.inspect} -> #{mutation.mutated_code.inspect}")
      end
      killed = results.count(&:killed)
      out.puts("#{results.size} mutations, #{killed} killed, #{results.size - killed} survived")
    end

    private_class_method :report
  end
end
