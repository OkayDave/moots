# frozen_string_literal: true

RSpec.describe Moots::Mutation do
  def mutation(**overrides)
    described_class.new(original_code: "a + b", mutated_code: "a - b", line_number: 2,
                        file_path: "math.rb", start_offset: 7, **overrides)
  end

  it "retains all location and expression metadata" do
    expect(mutation).to have_attributes(
      original_code: "a + b", mutated_code: "a - b", line_number: 2,
      file_path: "math.rb", start_offset: 7
    )
  end

  it "changes the requested occurrence and leaves frozen input intact" do
    source = "a + b; a + b"
    expect(mutation.apply(source)).to eq("a + b; a - b")
    expect(source).to eq("a + b; a + b")
  end

  it "supports length-changing replacements at the beginning and end of a file" do
    change = mutation(original_code: "a or b", mutated_code: "a and b", start_offset: 0)
    expect(change.apply("a or b")).to eq("a and b")
  end

  it "preserves the input encoding and multibyte prefix" do
    source = "é😀 a + b"
    changed = mutation.apply(source)
    expect(changed).to eq("é😀 a - b")
    expect(changed.encoding).to eq(Encoding::UTF_8)
  end

  it "preserves binary source bytes and CRLF endings" do
    source = "#\xFFabc\r\na + b\r\n".b
    changed = mutation.apply(source)
    expect(changed).to eq("#\xFFabc\r\na - b\r\n".b)
    expect(changed.encoding).to eq(Encoding::BINARY)
  end

  ["prefix x + y", "", "short"].each do |source|
    it "rejects stale or out-of-bounds source #{source.inspect}" do
      expect { mutation.apply(source) }.to raise_error(Moots::Error, /math.rb:2/)
    end
  end
end
