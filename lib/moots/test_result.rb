# frozen_string_literal: true

module Moots
  # The exit status and combined output of one test command.
  class TestResult
    attr_reader :output

    def initialize(success:, output:)
      @success = success
      @output = output
    end

    def success?
      @success
    end
  end
end
