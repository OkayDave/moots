# frozen_string_literal: true

require "rspec"
require_relative "lib/comparison_rules"
require_relative "cases"

cases = { "strong" => ComparisonCases::STRONG, "weak" => ComparisonCases::WEAK }.fetch(ARGV.shift)

RSpec.configure { |config| config.fail_if_no_examples = true }

RSpec.describe ComparisonRules do
  cases.each do |method, samples|
    it "checks #{method}" do
      samples.each do |left, right, expected|
        expect(described_class.public_send(method, left, right)).to be(expected)
      end
    end
  end
end

exit RSpec::Core::Runner.run(["--options", File::NULL, "--format", "progress", "--no-color"])
