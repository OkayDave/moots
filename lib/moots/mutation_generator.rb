# frozen_string_literal: true

require "parser/current"

module Moots
  class MutationGenerator
    ARITHMETIC_OPERATORS = {
      "+" => "-",
      "-" => "+",
      "*" => "/",
      "/" => "*"
    }.freeze

    BOOLEAN_OPERATORS = {
      "&&" => "||",
      "||" => "&&"
    }.freeze

    def generate_mutations(code)
      mutations = []
      buffer = Parser::Source::Buffer.new("(string)")
      buffer.source = code

      parser = Parser::CurrentRuby.new
      ast = parser.parse(buffer)

      return [] unless ast

      process_node(ast, mutations, buffer)
      mutations
    end

    private

    def process_node(node, mutations, buffer)
      case node.type
      when :send
        process_send_node(node, mutations, buffer)
      when :and, :or
        process_boolean_node(node, mutations, buffer)
      end

      node.children.each do |child|
        process_node(child, mutations, buffer) if child.is_a?(Parser::AST::Node)
      end
    end

    def process_send_node(node, mutations, buffer)
      return unless node.children[1].is_a?(Symbol)

      operator = node.children[1].to_s
      return unless ARITHMETIC_OPERATORS.key?(operator)

      generate_operator_mutation(node, operator, ARITHMETIC_OPERATORS[operator], mutations, buffer)
    end

    def process_boolean_node(node, mutations, buffer)
      operator = node.type == :and ? "&&" : "||"
      generate_operator_mutation(node, operator, BOOLEAN_OPERATORS[operator], mutations, buffer)
    end

    def generate_operator_mutation(node, original_op, mutated_op, mutations, buffer)
      original_range = node.loc.expression
      original_code = buffer.source[original_range.begin_pos...original_range.end_pos]
      mutated_code = original_code.gsub(original_op, mutated_op)

      mutations << Mutation.new(
        original_code: original_code,
        mutated_code: mutated_code,
        line_number: original_range.line,
        file_path: buffer.name
      )
    end
  end
end
