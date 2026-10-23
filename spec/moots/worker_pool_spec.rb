# frozen_string_literal: true

require "timeout"

RSpec.describe Moots::WorkerPool do
  around { |example| Timeout.timeout(3) { example.run } }

  it "overlaps workers, serializes callbacks on the caller and returns input order" do
    caller = Thread.current
    release_first = Queue.new
    events = []
    workers_used = Queue.new
    before = lambda do |item, index|
      expect(Thread.current).to eq(caller)
      events << [:started, item, index]
    end
    after = lambda do |result, index|
      expect(Thread.current).to eq(caller)
      events << [:finished, result, index]
      release_first << true if index == 1
    end
    results = described_class.new(%i[first second], before: before, after: after).map([10, 20, 30]) do |worker, item|
      workers_used << worker
      expect(events).to include([:started, item, [10, 20, 30].index(item)])
      release_first.pop if item == 10
      item.to_s
    end
    expect(results).to eq(%w[10 20 30])
    expect(events.select { |event| event.first == :finished }.map(&:last).first).to eq(1)
    expect(3.times.map { workers_used.pop }.uniq.sort).to eq(%i[first second])
  end

  it "handles empty work without executing operations or callbacks" do
    unexpected = ->(*) { raise "unexpected" }
    expect(described_class.new([:worker], before: unexpected, after: unexpected).map([], &unexpected)).to eq([])
  end

  [RuntimeError, ThreadError, Interrupt, SystemExit].each do |error|
    it "propagates #{error} and joins every worker after cancelling outstanding work" do
      running = Queue.new
      stopped = Queue.new
      pool = described_class.new(%i[one two], before: ->(*) {}, after: ->(*) {})
      expect do
        pool.map(%i[wait fail]) do |_worker, item|
          if item == :wait
            begin
              running << Thread.current
              sleep
            ensure
              stopped << Thread.current
            end
          else
            thread = running.pop
            running << thread
            raise error, "worker failed"
          end
        end
      end.to raise_error(error, "worker failed")
      expect(stopped.pop).to eq(running.pop)
      expect(stopped.empty?).to be(true)
    end
  end

  it "never runs a job if its starting callback fails" do
    pool = described_class.new([:worker], before: ->(*) { raise "callback" }, after: ->(*) {})
    operation = double("operation")
    expect(operation).not_to receive(:call)
    expect { pool.map([:job]) { operation.call } }.to raise_error("callback")
  end

  it "cancels active jobs if a finished callback raises, without leaking threads" do
    running = Queue.new
    stopped = Queue.new
    pool = described_class.new(%i[one two], before: ->(*) {}, after: ->(*) { raise Interrupt })
    expect do
      pool.map(%i[wait finish]) do |_worker, item|
        if item == :wait
          begin
            running << Thread.current
            sleep
          ensure
            stopped << Thread.current
          end
        else
          running.pop
          :finished
        end
      end
    end.to raise_error(Interrupt)
    expect(stopped.pop).not_to be_alive
  end
end
