# frozen_string_literal: true

require_relative "error"

module Moots
  # A single expression replacement, located by byte offset in the original source.
  class Mutation
    attr_reader :original_code, :mutated_code, :line_number, :file_path, :start_offset

    def initialize(original_code:, mutated_code:, line_number:, file_path:, start_offset:)
      @original_code = original_code
      @mutated_code = mutated_code
      @line_number = line_number
      @file_path = file_path
      @start_offset = start_offset
    end

    # Return a changed copy without touching the input or replacing other occurrences.
    def apply(code)
      bytes = code.b
      unless bytes.byteslice(start_offset, original_code.bytesize) == original_code.b
        raise Error, "Source no longer matches mutation at #{file_path}:#{line_number}"
      end

      bytes[start_offset, original_code.bytesize] = mutated_code.b
      bytes.force_encoding(code.encoding)
    end
  end
end
