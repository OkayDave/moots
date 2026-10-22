# frozen_string_literal: true

require "prism"
require_relative "mutation"

module Moots
  # Generate one mutation per supported operator using Prism's byte locations.
  class MutationGenerator
    ARITHMETIC_OPERATORS = { "+" => "-", "-" => "+", "*" => "/", "/" => "*" }.freeze
    BOOLEAN_OPERATORS = { "&&" => "||", "||" => "&&", "and" => "or", "or" => "and" }.freeze

    def generate_mutations(code, file_path: "(string)")
      parsed = Prism.parse(code)
      unless parsed.success?
        error = parsed.errors.first
        raise Error, "#{file_path}:#{error.location.start_line}: #{error.message}"
      end

      mutations = []
      nodes = [parsed.value]
      until nodes.empty?
        node = nodes.pop
        mutation = mutation_for(node, file_path)
        mutations << mutation if mutation
        nodes.concat(node.compact_child_nodes.reverse)
      end
      mutations
    end

    private

    def mutation_for(node, file_path)
      case node
      when Prism::CallNode
        replacement = ARITHMETIC_OPERATORS[node.name.to_s]
        return unless replacement

        location = node.message_loc
      when Prism::AndNode, Prism::OrNode
        location = node.operator_loc
        replacement = BOOLEAN_OPERATORS.fetch(location.slice)
      else
        return
      end

      expression = node.location
      mutated = expression.slice.b
      mutated[location.start_offset - expression.start_offset, location.length] = replacement
      Mutation.new(
        original_code: expression.slice,
        mutated_code: mutated.force_encoding(expression.slice.encoding),
        line_number: location.start_line,
        file_path: file_path,
        start_offset: expression.start_offset
      )
    end
  end
end
