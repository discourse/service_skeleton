# frozen_string_literal: true

require_relative "../../spec_helper"

require "service_skeleton"

describe ServiceSkeleton::Generator do
  uses_logger

  let(:env)          { {} }
  let(:service_name) { "spec_service" }
  let(:variables)    { [] }
  let(:config)       { ServiceSkeleton::Config.new(env, service_name, variables) }
  let(:registry)     { Prometheus::Client::Registry.new }
  let(:metrics)      { [] }
  let(:signals)      { {} }

  let(:ultravisor)   { instance_double(Ultravisor) }

  def generate
    ServiceSkeleton.generate(config: config, metrics_registry: registry, service_metrics: metrics, service_signal_handlers: signals)
  end

  before(:each) do
    allow(Ultravisor).to receive(:new).and_return(ultravisor)
    allow(ultravisor).to receive(:add_child)
  end

  describe ".ultravisor" do
    it "doesn't put a metrics server into the Ultravisor" do
      expect(ultravisor)
        .to_not receive(:add_child)
        .with(include(id: :metrics_server))

      generate
    end

    context "with METRICS_PORT defined" do
      let(:env) { { "SPEC_SERVICE_METRICS_PORT" => "54321" } }

      it "puts a metrics server into the Ultravisor" do
        expect(ultravisor)
          .to receive(:add_child)
          .with(include(id: :metrics_server))

        generate
      end
    end

    it "doesn't tell the logger to use logstash" do
      expect(logger.singleton_class).to_not receive(:prepend)

      generate
    end

    context "with LOGSTASH_SERVER defined" do
      let(:env) { { "#{service_name.upcase}_LOGSTASH_SERVER" => "logstash.example.com:5151" } }

      it "configures logstash forwarding" do
        expect(ultravisor)
          .to receive(:add_child)
          .with(include(id: :logstash_writer, args: include(include(server_name: "logstash.example.com:5151"))))

        generate
      end
    end

    it "puts a signal handler into the Ultravisor" do
      expect(ultravisor)
        .to receive(:add_child)
        .with(
          id: :signal_manager,
          klass: ServiceSkeleton::SignalManager,
          method: :run,
          args: [logger: logger, counter: instance_of(Prometheus::Client::Counter), signals: instance_of(Array)],
          shutdown: { method: :shutdown, timeout: 1 }
        )

      generate
    end

    describe "signal handler" do
      def handlers_for(spec)
        allow(ultravisor).to receive(:add_child) do |**kwargs|
          next ultravisor if kwargs[:id] != :signal_handler

          yield kwargs[:args].first[:signals].select { |s| s.first == spec }

          ultravisor
        end

        generate
      end

      it "makes USR1 increase logging level" do
        handlers_for("USR1") do |s|
          expect(s.length).to eq(1)

          allow(logger).to receive(:level).and_return(Logger::INFO)
          expect(logger).to receive(:level=).with(Logger::DEBUG)
          s.first.last.call
        end
      end

      it "makes USR2 decrease logging level" do
        handlers_for("USR2") do |s|
          expect(s.length).to eq(1)

          allow(logger).to receive(:level).and_return(Logger::WARN)
          expect(logger).to receive(:level=).with(Logger::ERROR)
          s.first.last.call
        end
      end

      it "makes HUP reopen the logger" do
        handlers_for("HUP") do |s|
          expect(s.length).to eq(1)

          expect(logger).to receive(:reopen)
          s.first.last.call
        end
      end

      it "makes QUIT do a sigdump" do
        handlers_for("QUIT") do |s|
          expect(s.length).to eq(1)

          expect(Sigdump).to receive(:dump).with("+")
          s.first.last.call
        end
      end

      %w{INT TERM}.each do |sig|
        it "makes #{sig} shutdown the ultravisor" do
          handlers_for(sig) do |s|
            expect(s.length).to eq(1)

            expect(ultravisor).to receive(:shutdown).with(wait: false, force: false)
            s.first.last.call
          end
        end

        it "makes #{sig} force-shutdown the ultravisor if called twice" do
          handlers_for(sig) do |s|
            expect(s.length).to eq(1)

            expect(ultravisor).to receive(:shutdown).with(wait: false, force: false).ordered
            expect(ultravisor).to receive(:shutdown).with(wait: false, force: true).ordered
            s.first.last.call
            s.first.last.call
          end
        end
      end

      context "with a service signal" do
        let(:signals)               { { spec_service: [["SYS", ->() { self.dup }]] } }
        let(:mock_ultravisor_child) { instance_double(Ultravisor::Child, "child") }
        let(:mock_worker_instance)  { instance_double(Object, "instance") }

        before(:each) do
          allow(ultravisor).to receive(:[]).and_return(mock_ultravisor_child)
          allow(mock_ultravisor_child).to receive(:unsafe_instance).and_return(mock_worker_instance)
          allow(mock_worker_instance).to receive(:dup)
        end

        it "passes in the class hook" do
          handlers_for("SYS") do |s|
            expect(s.length).to eq(1)
          end
        end

        it "goes looking for the worker object in the ultravisor" do
          handlers_for("SYS") do |s|
            expect(ultravisor).to receive(:[]).with(:spec_service).and_return(mock_ultravisor_child)
            s.first.last.call
          end
        end

        it "runs the block in the context of the worker object" do
          handlers_for("SYS") do |s|
            expect(mock_worker_instance).to receive(:dup)
            s.first.last.call
          end
        end
      end
    end

    describe "metrics setup" do
      let(:svc_class) { Class.new.tap { |k| k.include(ServiceSkeleton) } }
      let(:metrics)   { svc_class.registered_metrics }

      before(:each) do
        svc_class.counter(:ohai, docstring: "Say hi!")
        svc_class.counter(:"#{service_name}_ping", docstring: "Ping!")
      end

      it "defines prefixless accessor methods" do
        generate

        expect(registry.ohai).to be_a(Prometheus::Client::Counter)
        expect(registry.ping).to be_a(Prometheus::Client::Counter)
      end

      it "explodes if multiple metrics result in the same name" do
        svc_class.gauge(:"#{service_name}_ohai", docstring: "Hey again!")

        expect { generate }.to raise_error(ServiceSkeleton::Error::InvalidMetricNameError)
      end

      it "explodes if a metric method name conflicts with an existing method name" do
        svc_class.histogram(:"#{service_name}_counter", docstring: "Ah ah ah!")

        expect { generate }.to raise_error(ServiceSkeleton::Error::InvalidMetricNameError)
      end

      it "includes Ruby GC metrics" do
        generate

        expect(registry.get(:ruby_gc_count)).to be_a(Frankenstein::CollectedMetric)
      end

      it "includes Ruby VM metrics" do
        generate

        expect(registry.get(:ruby_vm_class_serial)).to be_a(Frankenstein::CollectedMetric)
      end

      it "includes process metrics" do
        generate

        expect(registry.get(:process_start_time_seconds)).to be_a(Prometheus::Client::Gauge)
      end

      it "doesn't register the metrics modules as methods" do
        %i{ruby_gc_count ruby_vm_class_serial process_start_time_seconds}.each do |m|
          expect(registry.methods).to_not include(m)
        end
      end
    end
  end
end
