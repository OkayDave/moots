# frozen_string_literal: true

require "open3"

module Moots
  class TestRunner
    def run_tests(command)
      stdout, stderr, status = Open3.capture3(command)
      output = [stdout, stderr].reject(&:empty?).join("\n").strip

      TestResult.new(
        success: status.success?,
        output: output
      )
    end
  end
end
