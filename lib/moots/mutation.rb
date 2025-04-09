# frozen_string_literal: true

module Moots
  class Mutation
    attr_reader :original_code, :mutated_code, :line_number, :file_path

    def initialize(original_code:, mutated_code:, line_number:, file_path:)
      @original_code = original_code
      @mutated_code = mutated_code
      @line_number = line_number
      @file_path = file_path
    end
  end
end
