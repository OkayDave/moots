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

  it "assigns reproducible IDs using relative paths and exact mutation bytes" do
    in_project do |directory|
      first = mutation(file_path: File.join(directory, "lib/math.rb"))
      copy = mutation(file_path: File.join(directory, "copy/lib/math.rb"))
      expect(first.id(root: directory)).to match(/\A[0-9a-f]{16}\z/)
      expect(first.relative_path(root: directory)).to eq("lib/math.rb")
      expect(copy.id(root: File.join(directory, "copy"))).to eq(first.id(root: directory))
      expect(mutation(file_path: "lib/math.rb").id).to eq(first.id)
      %i[file_path start_offset original_code mutated_code].zip(["other.rb", 8, "x + y", "a * b"]).each do |key, value|
        expect(mutation(key => value).id).not_to eq(mutation.id)
      end
      expect(mutation(original_code: "\xFF".b).id).to match(/\A[0-9a-f]{16}\z/)
    end
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
