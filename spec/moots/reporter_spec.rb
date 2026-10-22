# frozen_string_literal: true

RSpec.describe Moots::Reporter do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }
  let(:mutation) do
    Moots::Mutation.new(original_code: "déjà +\r\n  b", mutated_code: "déjà -\r\n  b",
                        line_number: 3, file_path: "lib/math.rb", start_offset: 12)
  end

  def result(killed, output = "test output")
    Moots::Result.new(mutation: mutation, killed: killed, test_result: test_result(!killed, output))
  end

  def reporter(format = "text", **options)
    described_class.new(format: format, out: out, err: err, **options)
  end

  it "streams and flushes progress, expression diffs and rerun arguments" do
    report = reporter
    killed = result(true)
    survived = result(false)
    expect(out).to receive(:flush).exactly(6).times
    report.call(type: :baseline_started)
    expect(out.string).to eq("Running baseline tests...\n")
    report.call(type: :baseline_passed)
    report.call(type: :mutation_started, mutation: mutation, index: 1, total: 2)
    expect(out.string).to include("[1/2] Testing #{mutation.id} lib/math.rb:3")
    report.call(type: :mutation_finished, result: killed)
    expect(out.string).not_to include("Expression diff", "Rerun argv")
    report.call(type: :mutation_finished, result: survived)
    report.finish([killed, survived])
    expect(out.string).to include("KILLED #{mutation.id}", "SURVIVED #{mutation.id}",
                                  "  - déjà +\n  -   b\n  + déjà -\n  +   b\n",
                                  "2 mutations, 1 killed, 1 survived\n")
    command = JSON.parse(out.string.lines.find { |line| line.include?("Rerun argv:") }.split("Rerun argv: ").last)
    expect(command).to eq(["bundle", "exec", "moots", "--mutation", mutation.id])
    expect(err.string).to eq("")
  end

  it "keeps progress on stderr and emits one versioned JSON document with exact metadata" do
    report = reporter("json", config_path: "config/custom tests.yml")
    results = [result(true, "assertion failed\n"), result(false, "passed\n")]
    report.call(type: :baseline_started)
    report.call(type: :baseline_passed)
    report.call(type: :mutation_started, mutation: mutation, index: 1, total: 2)
    results.each { |item| report.call(type: :mutation_finished, result: item) }
    expect(out.string).to eq("")
    report.finish(results)
    document = JSON.parse(out.string)
    expect(document).to include("schema_version" => 1, "status" => "completed",
                                "summary" => { "mutations" => 2, "killed" => 1, "survived" => 1 })
    expect(document.fetch("results")).to eq(results.map do |item|
      {
        "id" => mutation.id, "file" => "lib/math.rb", "line" => 3, "start_offset" => 12,
        "original" => "déjà +\r\n  b", "mutated" => "déjà -\r\n  b",
        "status" => item.killed ? "killed" : "survived", "test_output" => item.test_result.output,
        "rerun" => ["bundle", "exec", "moots", "--config", "config/custom tests.yml", "--mutation", mutation.id]
      }
    end)
    expect(err.string).to include("Running baseline", "Baseline passed", "[1/2] Testing", "KILLED", "SURVIVED")
  end

  it "replaces invalid UTF-8 output bytes without losing valid Unicode or breaking JSON" do
    report = reporter("json")
    report.finish([result(true, "é\xFF\n".b)])
    expect(JSON.parse(out.string).fetch("results").first.fetch("test_output")).to eq("é�\n")
  end

  it "prints text errors to stderr without a misleading summary" do
    reporter.error("disk full")
    expect(out.string).to eq("")
    expect(err.string).to eq("moots: disk full\n")
  end

  it "rejects unknown progress events" do
    expect { reporter.call(type: :unexpected) }.to raise_error(ArgumentError, /Unknown progress event/)
  end
end
