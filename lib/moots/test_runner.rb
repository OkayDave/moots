# frozen_string_literal: true

require "open3"
require "timeout"
require_relative "error"
require_relative "test_result"

module Moots
  # Execute suites with a deadline and concurrently drain both output streams.
  class TestRunner
    def run_tests(command, timeout: 60)
      options = Gem.win_platform? ? { new_pgroup: true } : { pgroup: true }
      Open3.popen3(*Array(command), **options) do |stdin, stdout, stderr, process|
        stdin.close
        readers = [stdout, stderr].map { |stream| Thread.new { stream.read } }
        completed = false
        begin
          result = Timeout.timeout(timeout) do
            status = process.value
            output = readers.map(&:value).reject(&:empty?).join("\n").strip
            raise Error, "Test command terminated by signal #{status.termsig}" if status.signaled?
            if [126, 127].include?(status.exitstatus)
              raise Error, "Test command could not execute (exit #{status.exitstatus}): #{output}"
            end

            TestResult.new(success: status.success?, output: output)
          end
          completed = true
          result
        ensure
          terminate(process.pid) unless completed
          readers.each(&:kill) unless completed
          readers.each(&:join)
        end
      end
    rescue Timeout::Error
      raise Error, "Test command timed out after #{timeout} seconds"
    rescue SystemCallError => e
      raise Error, "Cannot execute test command: #{e.message}"
    end

    private

    def terminate(pid)
      if Gem.win_platform?
        system("taskkill", "/PID", pid.to_s, "/T", "/F", out: File::NULL, err: File::NULL)
      else
        Process.kill("KILL", -pid)
      end
    rescue Errno::ESRCH
      # The process may have exited between the timeout and the kill.
      nil
    end
  end
end
