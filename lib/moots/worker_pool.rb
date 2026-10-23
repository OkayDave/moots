# frozen_string_literal: true

module Moots
  # Run work concurrently, but deliver callbacks and exceptions on the calling thread.
  class WorkerPool
    def initialize(workers, before:, after:)
      @workers = workers
      @before = before
      @after = after
    end

    def map(items, &operation)
      pending = Queue.new
      items.each_with_index { |item, index| pending << [item, index] }
      events = Queue.new
      threads = []
      begin
        @workers.each { |worker| threads << start_worker(worker, pending, events, operation) }
        results = collect(items.size, events)
        threads.each(&:join)
        results
      ensure
        threads.each(&:kill)
        threads.each(&:join)
      end
    end

    private

    def take(queue)
      queue.pop(true)
    rescue ThreadError
      nil
    end

    def start_worker(worker, pending, events, operation)
      Thread.new do
        while (entry = take(pending))
          item, index = entry
          ready = Queue.new
          events << [:started, index, item, ready]
          ready.pop
          result = operation.call(worker, item)
          events << [:finished, index, result]
        end
      # Relay every worker exception, including Interrupt, so the caller never waits forever.
      rescue Exception => e # rubocop:disable Lint/RescueException
        events << [:failed, e]
      end
    end

    def collect(total, events)
      results = Array.new(total)
      total.times do
        index, value = next_result(events)
        results[index] = value
        @after.call(value, index)
      end
      results
    end

    def next_result(events)
      loop do
        type, index, value, ready = events.pop
        if type == :started
          @before.call(value, index)
          ready << true
        elsif type == :failed
          raise index
        else
          return [index, value]
        end
      end
    end
  end
end
