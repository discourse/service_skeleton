# frozen_string_literal: true

require_relative "./spec_helper"
require_relative "./spec_service"

require "service_skeleton"

describe ServiceSkeleton do
  uses_logger

  let(:env) { {} }
  let(:svc) { SpecService.new(env) }
  let(:mock_signal_handler) { instance_double(ServiceSkeleton::SignalHandler) }

  before(:each) do
    allow(ServiceSkeleton::SignalHandler).to receive(:new).and_return(mock_signal_handler)
    allow(mock_signal_handler).to receive(:hook_signal)
    allow(mock_signal_handler).to receive(:start!)
    allow(mock_signal_handler).to receive(:stop!)
  end

  it "can be sub-classed" do
    expect { class SpecService < ServiceSkeleton; end }.to_not raise_error
  end

  describe "#start" do
    it "explodes if the #run method hasn't been overridden" do
      expect { ServiceSkeleton.new({}).start }.to raise_error(ServiceSkeleton::Error::InheritanceContractError)
    end

    it "runs the service's #run method" do
      expect(svc).to receive(:run).with(no_args)

      svc.start
    end

    context "when #run raises an exception" do
      let(:env) { { "RAISE_EXCEPTION" => "StandardError" } }

      it "logs the exception" do
        expect(logger).to receive(:error) do |progname, &blk|
          expect(progname).to eq("SpecService#start")
          expect(blk.call).to match(/StandardError/)
        end

        expect { svc.start }.to_not raise_error
      end
    end

    it "doesn't start a metrics server by default" do
      expect(Frankenstein::Server).to_not receive(:new)

      svc.start
    end

    context "with a metrics port set" do
      let(:env) { { "SPEC_SERVICE_METRICS_PORT" => "54321" } }

      it "starts a metrics server" do
        mock_metrics_server = instance_double(Frankenstein::Server)

        expect(Frankenstein::Server).to receive(:new).with(port: 54321, logger: logger, metrics_prefix: :metrics_server, registry: instance_of(Prometheus::Client::Registry)).and_return(mock_metrics_server)
        expect(mock_metrics_server).to receive(:run)
        expect(logger).to receive(:info).with("SpecService#start_metrics_server")

        svc.start
      end
    end

    it "starts a signal watcher" do
      expect(ServiceSkeleton::SignalHandler).to receive(:new).and_return(mock_signal_handler)
      expect(mock_signal_handler).to receive(:start!)

      svc.start
    end
  end

  describe "#stop" do
    before(:each) do
      allow(svc).to receive(:shutdown)
    end

    it "calls the service's shutdown method" do
      expect(svc).to receive(:shutdown)

      svc.stop
    end

    it "calls shutdown on the metrics server if there is one running" do
      svc.instance_variable_set(:@metrics_server, mock_metrics_server = instance_double(Frankenstein::Server))
      expect(mock_metrics_server).to receive(:shutdown)

      svc.stop
    end
  end

  describe "#service_name" do
    it "calculates the service name from the class name" do
      expect(SpecService.new({}).__send__(:service_name)).to eq("spec_service")
    end

    it "safely handles an anonymous class" do
      klass = Class.new(ServiceSkeleton)

      expect { klass.new({}) }.to_not raise_error
      expect(klass.new({}).__send__(:service_name)).to match(/class_0x\h+/)
    end
  end

  describe "#config" do
    it "returns a config object" do
      expect(SpecService.new({}).config).to be_a(ServiceSkeleton::Config)
    end
  end

  describe "#logger" do
    it "returns a logger" do
      expect(SpecService.new({}).logger).to be_a(Logger)
    end
  end

  describe "#metrics" do
    it "returns a metrics registry" do
      expect(SpecService.new({}).metrics).to be_a(Prometheus::Client::Registry)
    end
  end

  describe ".config_class" do
    context "set to the default" do
      it "provides a ServiceSkeleton::Config object" do
        svc = SpecService.new({})
        expect(svc.config).to be_a(ServiceSkeleton::Config)
      end
    end

    context "set to a separate class" do
      let(:mock_config) { double(ServiceSkeleton::Config) }

      before(:each) do
        allow(CustomConfig).to receive(:new).with(instance_of(Hash), instance_of(ConfigService)).and_return(mock_config)
        allow(mock_config).to receive(:logger).and_return(logger)
        allow(mock_config).to receive(:metrics_port).and_return(nil)
      end

      it "instantiates the other class" do
        svc = ConfigService.new({})

        expect(svc.config).to eq(mock_config)
      end
    end
  end

  describe "signal handler" do
    before(:each) do
      # Override the default stubbing of the signal handler
      allow(ServiceSkeleton::SignalHandler).to receive(:new).and_call_original
    end

    def call_signal_handler(sig)
      svc
        .instance_variable_get(:@signal_handler)
        .instance_variable_get(:@signal_registry)
        .find { |s| s[:signal] =~ /#{sig}/ }[:callback]
        .call(42)
    end

    describe "for USR1" do
      it "increases the default logging verbosity" do
        expect(logger).to receive(:level).at_least(:once).and_return(1)
        expect(logger).to receive(:level=).with(0)
        expect(logger).to receive(:info)

        call_signal_handler("USR1")
      end
    end

    describe "for USR2" do
      it "decreases the default logging verbosity" do
        expect(logger).to receive(:level).at_least(:once).and_return(1)
        expect(logger).to receive(:level=).with(2)
        expect(logger).to receive(:info)

        call_signal_handler("USR2")
      end
    end

    describe "for HUP" do
      it "reopens the logger" do
        expect(logger).to receive(:reopen)
        expect(logger).to receive(:info)

        call_signal_handler("HUP")
      end
    end

    describe "for QUIT" do
      it "spams stderr mercilessly" do
        expect(STDERR).to receive(:write).at_least(:once)
        expect(STDERR).to receive(:flush).at_least(:once)

        call_signal_handler("QUIT")
      end
    end

    describe "for INT" do
      it "tells the service to give it away" do
        expect(svc).to receive(:stop)

        call_signal_handler("INT")
      end
    end

    describe "for TERM" do
      it "tells the service to give it away" do
        expect(svc).to receive(:stop)

        call_signal_handler("TERM")
      end
    end
  end

  describe "#hook_signal" do
    before(:each) do
      # Override the default stubbing of the signal handler
      allow(ServiceSkeleton::SignalHandler).to receive(:new).and_call_original
    end

    it "adds a spec to the signal registry" do
      tripped = false

      svc.hook_signal("CONT") { tripped = true }

      svc
        .instance_variable_get(:@signal_handler)
        .instance_variable_get(:@signal_registry)
        .find { |s| s[:signal] =~ /CONT/ }[:callback]
        .call(42)
    end
  end
end
