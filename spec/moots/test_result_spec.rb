# frozen_string_literal: true

RSpec.describe Moots::TestResult do
  [true, false].each do |success|
    it "retains success=#{success} and complete output" do
      result = described_class.new(success: success, output: "  output\n")
      expect(result.success?).to be(success)
      expect(result.output).to eq("  output\n")
    end
  end

  it "exposes the gem version as a valid release version" do
    expect(Gem::Version.new(Moots::VERSION).to_s).to eq(Moots::VERSION)
  end
end
