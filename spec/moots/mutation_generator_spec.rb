# frozen_string_literal: true

RSpec.describe Moots::MutationGenerator do
  let(:generator) { described_class.new }

  describe "#generate_mutations" do
    context "with arithmetic operators" do
      let(:code) { "def add(a, b); a + b; end" }

      it "generates mutations for arithmetic operators" do
        mutations = generator.generate_mutations(code)

        expect(mutations).to include(
          have_attributes(
            original_code: "a + b",
            mutated_code: "a - b",
            line_number: 1
          )
        )
      end

      it "handles multiple operators in the same line" do
        code = "def calculate(a, b, c); a + b * c; end"
        mutations = generator.generate_mutations(code)

        expect(mutations.size).to eq(2)
        expect(mutations).to include(
          have_attributes(
            original_code: "a + b * c",
            mutated_code: "a - b * c",
            line_number: 1
          )
        )
        expect(mutations).to include(
          have_attributes(
            original_code: "b * c",
            mutated_code: "b / c",
            line_number: 1
          )
        )
      end
    end

    context "with boolean operators" do
      let(:code) { "def valid?(value); value && value > 0; end" }

      it "generates mutations for boolean operators" do
        mutations = generator.generate_mutations(code)

        expect(mutations).to include(
          have_attributes(
            original_code: "value && value > 0",
            mutated_code: "value || value > 0",
            line_number: 1
          )
        )
      end

      it "handles nested boolean expressions" do
        code = "def complex?(a, b, c); a && (b || c); end"
        mutations = generator.generate_mutations(code)

        expect(mutations.size).to eq(2)
        expect(mutations).to include(
          have_attributes(
            original_code: "a && (b || c)",
            mutated_code: "a || (b || c)",
            line_number: 1
          )
        )
        expect(mutations).to include(
          have_attributes(
            original_code: "b || c",
            mutated_code: "b && c",
            line_number: 1
          )
        )
      end
    end

    context "with invalid code" do
      it "returns an empty array for syntax errors" do
        code = "def invalid; a + b" # Missing end
        mutations = generator.generate_mutations(code)
        expect(mutations).to be_empty
      end

      it "returns an empty array for empty code" do
        mutations = generator.generate_mutations("")
        expect(mutations).to be_empty
      end
    end

    context "with file handling" do
      it "includes the file path in mutations" do
        buffer = Parser::Source::Buffer.new("test.rb")
        buffer.source = "def test; 1 + 2; end"

        mutations = generator.generate_mutations(buffer.source)
        expect(mutations.first.file_path).to eq("(string)")
      end
    end
  end
end
