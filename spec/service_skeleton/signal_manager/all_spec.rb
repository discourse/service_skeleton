# frozen_string_literal: true

require_relative "../../spec_helper"

require "service_skeleton"

describe ServiceSkeleton::SignalManager do
  uses_logger

  let(:signals) { [] }
  let(:counter) { instance_double(Prometheus::Client::Counter) }

  let(:sm) { ServiceSkeleton::SignalManager.new(logger: logger, signals: signals, counter: counter) }

  before(:each) do
    allow(counter).to receive(:increment)
  end

  describe "#initialize" do
    it "accepts a sigspec as a short string" do
      sm = ServiceSkeleton::SignalManager.new(logger: logger, counter: counter, signals: [["INT", ->() {}]])

      expect(sm.instance_variable_get(:@registry)).to have_key(Signal.list["INT"])
    end

    it "accepts a sigspec as a long string" do
      sm = ServiceSkeleton::SignalManager.new(logger: logger, counter: counter, signals: [["SIGINT", ->() {}]])

      expect(sm.instance_variable_get(:@registry)).to have_key(Signal.list["INT"])
    end

    it "accepts a sigspec as a lowercase string" do
      sm = ServiceSkeleton::SignalManager.new(logger: logger, counter: counter, signals: [["int", ->() {}]])

      expect(sm.instance_variable_get(:@registry)).to have_key(Signal.list["INT"])
    end

    it "accepts a sigspec as a symbol" do
      sm = ServiceSkeleton::SignalManager.new(logger: logger, counter: counter, signals: [[:SIGINT, ->() {}]])

      expect(sm.instance_variable_get(:@registry)).to have_key(Signal.list["INT"])
    end

    it "accepts a sigspec as an integer" do
      sm = ServiceSkeleton::SignalManager.new(logger: logger, counter: counter, signals: [[7, ->() {}]])

      expect(sm.instance_variable_get(:@registry)).to have_key(7)
    end

    [
      "NOTASIGNAL",
      :NOTASIGNAL,
      "SIGNOT",
      3.14159625,
      { signal: "INT" },
    ].each do |s|
      it "raises an exception for invalid sigspec #{s}" do
        expect { ServiceSkeleton::SignalManager.new(logger: logger, counter: counter, signals: [[s, ->() {}]]) }.to raise_error(ArgumentError)
      end
    end
  end

  describe "#run" do
    before(:each) do
      allow(sm).to receive(:signals_loop)
      allow(Signal).to receive(:trap)
    end

    context "with no signals" do
      it "just sits quietly" do
        expect(sm).to receive(:signals_loop)

        sm.run
      end
    end

    context "with signals" do
      let(:signals) { [["INT", ->() {}], ["WINCH", ->() {}]] }

      it "hooks the signals" do
        expect(Signal).to receive(:trap).with(Signal.list["INT"])
        expect(Signal).to receive(:trap).with(Signal.list["WINCH"])

        sm.run
      end
    end
  end

  describe "#handle_signal" do
    let(:mock_proc) { instance_double(Proc) }
    before(:each) do
      allow(mock_proc).to receive(:call)
    end

    let(:signals) { [["INT", mock_proc]] }

    context "when given a registered signal" do
      it "calls the associated handler proc" do
        expect(mock_proc).to receive(:call)

        sm.__send__(:handle_signal, Signal.list["INT"].chr)
      end

      it "increments the counter" do
        expect(counter).to receive(:increment).with(labels: { signal: "INT" })

        sm.__send__(:handle_signal, Signal.list["INT"].chr)
      end
    end

    context "when the handler proc raises an exception" do
      before(:each) do
        allow(logger).to receive(:error)
      end

      it "logs an error" do
        expect(mock_proc).to receive(:call).and_raise(RuntimeError)
        expect(logger).to receive(:error)

        sm.__send__(:handle_signal, Signal.list["INT"].chr)
      end

      it "increments the counter" do
        expect(counter).to receive(:increment).with(labels: { signal: "INT" })

        sm.__send__(:handle_signal, Signal.list["INT"].chr)
      end
    end

    context "when given an unregistered signal" do
      before(:each) do
        allow(logger).to receive(:error)
      end

      it "logs an error" do
        expect(logger).to receive(:error)

        sm.__send__(:handle_signal, Signal.list["WINCH"].chr)
      end
    end
  end

  describe "#shutdown" do
    before(:each) do
      allow(sm).to receive(:signals_loop)
    end

    it "closes the read end of the sigchar pipe" do
      sm.run

      expect(sm.instance_variable_get(:@r)).to receive(:close)

      sm.shutdown
    end
  end
end
