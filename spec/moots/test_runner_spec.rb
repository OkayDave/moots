# frozen_string_literal: true

RSpec.describe Moots::TestRunner do
  let(:runner) { described_class.new }

  describe "#run_tests" do
    context "when tests pass" do
      it "returns a successful result with empty output" do
        allow(Open3).to receive(:capture3).with("bundle exec rspec").and_return(["", "",
                                                                                 instance_double(Process::Status, success?: true)])

        result = runner.run_tests("bundle exec rspec")

        expect(result).to be_success
        expect(result.output).to be_empty
      end

      it "handles test output with newlines" do
        output = "Running tests...\n\nAll tests passed!"
        allow(Open3).to receive(:capture3).with("bundle exec rspec").and_return([output, "",
                                                                                 instance_double(Process::Status, success?: true)])

        result = runner.run_tests("bundle exec rspec")

        expect(result).to be_success
        expect(result.output).to eq("Running tests...\n\nAll tests passed!")
      end
    end

    context "when tests fail" do
      it "returns a failed result with error output" do
        error_output = "1) Example test\n   Failure/Error: expect(true).to be false"
        allow(Open3).to receive(:capture3).with("bundle exec rspec").and_return(
          ["", error_output, instance_double(Process::Status, success?: false)]
        )

        result = runner.run_tests("bundle exec rspec")

        expect(result).not_to be_success
        expect(result.output).to include("Failure/Error")
      end

      it "combines stdout and stderr when both have content" do
        stdout = "Running tests..."
        stderr = "Error: Something went wrong"
        allow(Open3).to receive(:capture3).with("bundle exec rspec").and_return(
          [stdout, stderr, instance_double(Process::Status, success?: false)]
        )

        result = runner.run_tests("bundle exec rspec")

        expect(result.output).to eq("Running tests...\nError: Something went wrong")
      end
    end

    context "with different test commands" do
      it "handles custom test commands" do
        custom_command = "rake test"
        allow(Open3).to receive(:capture3).with(custom_command).and_return(["", "",
                                                                            instance_double(Process::Status, success?: true)])

        result = runner.run_tests(custom_command)

        expect(result).to be_success
      end

      it "handles test commands with arguments" do
        command = "bundle exec rspec spec/specific_test.rb"
        allow(Open3).to receive(:capture3).with(command).and_return(["", "",
                                                                     instance_double(Process::Status, success?: true)])

        result = runner.run_tests(command)

        expect(result).to be_success
      end
    end
  end
end
