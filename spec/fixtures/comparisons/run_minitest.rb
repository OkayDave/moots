# frozen_string_literal: true

require "minitest/autorun"
require_relative "lib/comparison_rules"
require_relative "cases"

cases = { "strong" => ComparisonCases::STRONG, "weak" => ComparisonCases::WEAK }.fetch(ARGV.shift)

# Exercise the same behavioral expectations through an independent test runner.
class ComparisonTest < Minitest::Test; end

cases.each do |method, samples|
  ComparisonTest.define_method("test_#{method}") do
    samples.each do |left, right, expected|
      assert_equal expected, ComparisonRules.public_send(method, left, right)
    end
  end
end
