# frozen_string_literal: true

RSpec.describe Moots::Configuration do
  it "provides usable defaults" do
    expect(described_class.new.to_h).to eq(
      include: ["app/**/*.rb",
                "lib/**/*.rb"], exclude: [], test_command: "bundle exec rspec", timeout: 60, mutation: nil
    )
  end

  it "normalizes YAML keys and retains explicit overrides" do
    expect(described_class.new("include" => ["src/*.rb"], "exclude" => ["src/skip.rb"],
                               "test_command" => ["ruby", "tests.rb"], "timeout" => 0.5).to_h)
      .to eq(include: ["src/*.rb"], exclude: ["src/skip.rb"], test_command: ["ruby", "tests.rb"], timeout: 0.5,
             mutation: nil)
  end

  it "does not mutate the supplied hash or expose its internal hash" do
    input = { timeout: 2 }.freeze
    configuration = described_class.new(input)
    configuration.to_h[:timeout] = 10
    expect(configuration.to_h[:timeout]).to eq(2)
    expect(input).to eq(timeout: 2)
  end

  [nil, false, [], "", 1].each do |value|
    it "rejects a non-mapping #{value.inspect}" do
      expect { described_class.new(value) }.to raise_error(Moots::Error, /mapping/)
    end
  end

  it "rejects misspelled and unknown keys" do
    expect { described_class.new(typo: true) }.to raise_error(Moots::Error, /Unknown configuration keys: typo/)
  end

  %i[include exclude].each do |key|
    [nil, "*.rb", [nil], [1], [""], ["  "], ["a\0b"]].each do |value|
      it "rejects #{key}: #{value.inspect}" do
        expect { described_class.new(key => value) }.to raise_error(Moots::Error, /#{key} must be/)
      end
    end
  end

  [nil, "", " ", [], [""], ["ruby", nil], ["ruby", ""], 12, "a\0b"].each do |value|
    it "rejects command #{value.inspect}" do
      expect { described_class.new(test_command: value) }.to raise_error(Moots::Error, /test_command must be/)
    end
  end

  [nil, "10", 0, -1, Float::INFINITY, Float::NAN, Complex(1, 1)].each do |value|
    it "rejects timeout #{value.inspect}" do
      expect { described_class.new(timeout: value) }.to raise_error(Moots::Error, /timeout must be/)
    end
  end

  it "loads YAML from a file" do
    in_project do
      File.write("config.yml", "include: [src/*.rb]\ntest_command: ruby test.rb\ntimeout: 2\n")
      expect(described_class.load("config.yml")).to eq(
        include: ["src/*.rb"], exclude: [], test_command: "ruby test.rb", timeout: 2, mutation: nil
      )
    end
  end

  ["--- !ruby/object:Object {}", "include: [", "include: &files [a.rb]\nexclude: *files"].each do |yaml|
    it "rejects unsafe or malformed YAML #{yaml.inspect}" do
      in_project do
        File.write("config.yml", yaml)
        expect do
          described_class.load("config.yml")
        end.to raise_error(Moots::Error, /Cannot load configuration config.yml/)
      end
    end
  end

  it "rejects an empty configuration file" do
    in_project do
      File.write("config.yml", "")
      expect { described_class.load("config.yml") }.to raise_error(Moots::Error, /mapping/)
    end
  end

  it "reports a missing file" do
    in_project do
      expect { described_class.load("absent.yml") }.to raise_error(Moots::Error, /Cannot load configuration absent.yml/)
    end
  end

  it "accepts a specific mutation ID" do
    expect(described_class.new(mutation: "0123456789abcdef").to_h[:mutation]).to eq("0123456789abcdef")
  end

  [12, false, "", "0" * 15, "0" * 17, "ABCDEF0123456789", "g" * 16, "#{"0" * 16}\n"].each do |value|
    it "rejects malformed mutation ID #{value.inspect}" do
      expect { described_class.new(mutation: value) }.to raise_error(Moots::Error, /mutation must be/)
    end
  end
end
