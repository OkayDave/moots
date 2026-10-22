# frozen_string_literal: true

RSpec.describe Moots::MutationGenerator do
  subject(:generator) { described_class.new }

  def changes(code)
    generator.generate_mutations(code).map { |mutation| mutation.apply(code) }
  end

  { "+" => "-", "-" => "+", "*" => "/", "/" => "*",
    "==" => "!=", "!=" => "==", ">" => ">=", ">=" => ">", "<" => "<=", "<=" => "<",
    "&&" => "||", "||" => "&&", "and" => "or", "or" => "and" }.each do |original, replacement|
    it "mutates #{original} to #{replacement}" do
      code = "def calculate(a, b); a #{original} b; end"
      mutations = generator.generate_mutations(code, file_path: "example.rb")
      expect(mutations.size).to eq(1)
      expect(mutations.first).to have_attributes(
        original_code: "a #{original} b", mutated_code: "a #{replacement} b",
        file_path: "example.rb", line_number: 1, start_offset: 21
      )
      expect(mutations.first.apply(code)).to eq("def calculate(a, b); a #{replacement} b; end")
    end
  end

  {
    "a + b + c" => ["a + b - c", "a - b + c"],
    "a + b * c" => ["a - b * c", "a + b / c"],
    "a && (b || c)" => ["a || (b || c)", "a && (b && c)"],
    "a && b && c" => ["a && b || c", "a || b && c"],
    "a + b; a + b" => ["a - b; a + b", "a + b; a - b"],
    "a > b; a > b" => ["a >= b; a > b", "a > b; a >= b"],
    "(a == b) != c" => ["(a == b) == c", "(a != b) != c"],
    "a + b <= c && d != e" => ["a + b <= c || d != e", "a + b < c && d != e",
                               "a - b <= c && d != e", "a + b <= c && d == e"],
    '"a>=b" >= "c<d" # >= stays here' => ['"a>=b" > "c<d" # >= stays here'],
    "a.==(b)" => ["a.!=(b)"],
    "a&.<=(b)" => ["a&.<(b)"],
    "# é 😀\r\ndéjà <\r\n  limite\r\n" => ["# é 😀\r\ndéjà <=\r\n  limite\r\n"],
    "# é 😀\r\ndéjà >=\r\n  limite\r\n" => ["# é 😀\r\ndéjà >\r\n  limite\r\n"],
    'puts "#{a > b}"' => ['puts "#{a >= b}"'],
    '"a+b" + "c+d" # a+b' => ['"a+b" - "c+d" # a+b'],
    "a + /x+y/" => ["a - /x+y/"],
    "a.+(b)" => ["a.-(b)"],
    "a&.+(b)" => ["a&.-(b)"],
    "a +\n  b" => ["a -\n  b"],
    "# é 😀\r\na + b\r\n" => ["# é 😀\r\na - b\r\n"],
    "déjà = 1; déjà + 2" => ["déjà = 1; déjà - 2"],
    'puts "#{1 + 2}"' => ['puts "#{1 - 2}"'],
    "def add(a, b) = a + b" => ["def add(a, b) = a - b"],
    "[1].map { it + 2 }" => ["[1].map { it - 2 }"],
    "case data; in {x:}; x + 1; end" => ["case data; in {x:}; x - 1; end"],
    "def f(**); g(**); 1 + 2; end" => ["def f(**); g(**); 1 - 2; end"],
    "a = <<~TEXT\n  plus + minus -\nTEXT\na + b\n" => ["a = <<~TEXT\n  plus + minus -\nTEXT\na - b\n"],
    "a + b\n__END__\nc + d\n" => ["a - b\n__END__\nc + d\n"]
  }.each do |code, expected|
    it "changes exactly one operator in #{code.inspect}" do
      expect(changes(code)).to eq(expected)
      changes(code).each { |changed| expect(Prism.parse(changed)).to be_success }
    end
  end

  ["", "# comment\n", "42", '"a + b && c"', "/a+b/", "+a; -b; !c; ~d",
   "a === b; a <=> b; a =~ b; a !~ b; a % b; a ** b", "a += 1; b ||= 2; c &&= 3",
   "def +(other); other; end", "def ==(other); other; end", "def <=(other); other; end",
   ':==; :!=; :>; :>=; :<; :<=; "a == b"; /a>=b/ # a <= b', "foo; obj.foo; [1, 2]"].each do |code|
    it "does not invent mutations for #{code.inspect}" do
      expect(generator.generate_mutations(code)).to be_empty
    end
  end

  it "reports an operator's actual line in a multiline expression" do
    mutation = generator.generate_mutations("a\n  .+(b)", file_path: "math.rb").first
    expect(mutation.line_number).to eq(2)
    expect(mutation.apply("a\n  .+(b)")).to eq("a\n  .-(b)")
  end

  it "defaults the file label for strings" do
    expect(generator.generate_mutations("1 + 2").first.file_path).to eq("(string)")
  end

  it "preserves byte offsets and operator lines for comparisons after multibyte text" do
    code = "# é 😀\r\ndéjà\r\n  .>=(limite)\r\n"
    mutation = generator.generate_mutations(code, file_path: "boundary.rb").first
    expect(mutation).to have_attributes(
      original_code: "déjà\r\n  .>=(limite)", mutated_code: "déjà\r\n  .>(limite)",
      line_number: 3, file_path: "boundary.rb", start_offset: "# é 😀\r\n".bytesize
    )
    expect(mutation.apply(code)).to eq("# é 😀\r\ndéjà\r\n  .>(limite)\r\n")
  end

  ["def broken; a + b", "a +", "a + b\n)"].each do |code|
    it "rejects invalid syntax without reporting partial mutations: #{code.inspect}" do
      expect { generator.generate_mutations(code, file_path: "broken.rb") }
        .to raise_error(Moots::Error, /broken.rb:\d+:/)
    end
  end

  it "can be reused after an invalid input" do
    expect { generator.generate_mutations("def broken") }.to raise_error(Moots::Error)
    expect(changes("1 + 2")).to eq(["1 - 2"])
  end
end
