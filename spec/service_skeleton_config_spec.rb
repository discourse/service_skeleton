# frozen_string_literal: true

require_relative "./spec_helper"
require_relative "./spec_service"

require "service_skeleton"
require "service_skeleton/config"
require "service_skeleton/error"

describe ServiceSkeleton::Config do
  let(:env)    { {} }
  let(:svc)    { SpecService.new({}) }
  let(:vars)   { [] }
  let(:config) { ServiceSkeleton::Config.new(env, svc) }

  before(:each) do
    allow(svc).to receive(:registered_variables).with(no_args).and_return(svc.class.registered_variables + vars)
  end

  describe "#logger" do
    it "returns a logger" do
      expect(config.logger).to be_a(Logger)
    end

    it "logs to stderr" do
      expect(Logger).to receive(:new).with($stderr, 3, 1048576).and_call_original

      config
    end

    it "formats messages sanely" do
      expect(config.logger.formatter.call("WARN", Time.now, "Spec", "ohai!"))
        .to match(/\A\d+#0 W \[Spec\] ohai!\n\z/)
    end

    it "includes a thread number" do
      expect(Thread.new { config.logger.formatter.call("WARN", Time.now, "Spec", "ohai!") }.value)
        .to match(/\A\d+#1 W \[Spec\] ohai!\n\z/)
    end

    it "doesn't configure Loggerstash by default" do
      expect(Loggerstash).to_not receive(:new)

      config.logger
    end

    context "with a logstash server set" do
      let(:env) { { "SPEC_SERVICE_LOGSTASH_SERVER" => "logstash.example.com:5151" } }

      it "configures loggerstash" do
        expect(Loggerstash).to receive(:new).with(logstash_server: "logstash.example.com:5151", logger: an_instance_of(Logger)).and_return(mock_loggerstash = instance_double(Loggerstash))
        expect(mock_loggerstash).to receive(:metrics_registry=).with(an_instance_of(Prometheus::Client::Registry)).ordered
        expect(mock_loggerstash).to receive(:attach).with(an_instance_of(Logger)).ordered

        config.logger
      end
    end

    context "with LOG_LEVEL set to a single severity" do
      let(:env) { { "SPEC_SERVICE_LOG_LEVEL" => "warn" } }

      it "returns a suitably-configured logger" do
        expect(config.logger.level).to eq(Logger::WARN)
        expect(config.logger.filters).to eq([])
      end
    end

    context "with LOG_LEVEL set to something complicated" do
      let(:env) { { "SPEC_SERVICE_LOG_LEVEL" => "warn ,buggy=DeBuG, /noisy/i = ERROR" } }

      it "returns a suitably-configured logger" do
        expect(config.logger.level).to eq(Logger::WARN)
        expect(config.logger.filters).to eq([["buggy", Logger::DEBUG], [/noisy/i, Logger::ERROR]])
      end
    end

    context "with an invalid severity" do
      let(:env) { { "SPEC_SERVICE_LOG_LEVEL" => "ohai!" } }

      it "freaks out" do
        expect { config }.to raise_error(ServiceSkeleton::Error::InvalidEnvironmentError)
      end
    end

    context "with an invalid severity in a progname match" do
      let(:env) { { "SPEC_SERVICE_LOG_LEVEL" => "info,fred=ohai!" } }

      it "freaks out" do
        expect { config }.to raise_error(ServiceSkeleton::Error::InvalidEnvironmentError)
      end
    end

    context "with LOG_TIMESTAMPS enabled" do
      let(:env) { { "SPEC_SERVICE_LOG_ENABLE_TIMESTAMPS" => "yes" } }

      it "formats the log entries with a timestamp" do
        expect(config.logger.formatter.call("INFO", Time.strptime("1234567890.987654321", "%s.%N"), "Stamped", "ohai!"))
          .to match(/\A2009-02-13T23:31:30.987654321Z \d+#0 I \[Stamped\] ohai!\n\z/)
      end
    end

    context "with LOG_FILE specified" do
      let(:env) { { "SPEC_SERVICE_LOG_FILE" => "/var/log/spec_service.log" } }

      it "configures the logger appropriately" do
        expect(Logger::LogDevice).to receive(:new).with("/var/log/spec_service.log", include(shift_age: 3, shift_size: 1048576))

        config
      end
    end

    context "with LOG_MAX_FILE_SIZE specified" do
      let(:env) { { "SPEC_SERVICE_LOG_MAX_FILE_SIZE" => "1234567" } }

      it "configures the logger appropriately" do
        expect(Logger::LogDevice).to receive(:new).with($stderr, include(shift_age: 3, shift_size: 1234567))

        config
      end
    end

    context "with LOG_MAX_FILE_SIZE=0" do
      let(:env) { { "SPEC_SERVICE_LOG_MAX_FILE_SIZE" => "0" } }

      it "configures the logger appropriately" do
        expect(Logger::LogDevice).to receive(:new).with($stderr, include(shift_age: 0, shift_size: 0))

        config
      end
    end

    context "with LOG_MAX_FILES specified" do
      let(:env) { { "SPEC_SERVICE_LOG_MAX_FILES" => "42" } }

      it "configures the logger appropriately" do
        expect(Logger::LogDevice).to receive(:new).with($stderr, include(shift_age: 42, shift_size: 1048576))

        config
      end
    end
  end

  describe "#[]" do
    let(:env) { { "OHAI" => "there" } }

    it "allows access to the provided environment" do
      expect(config["OHAI"]).to eq("there")
    end
  end

  context "with defined variables" do
    let(:vars) do
      [
        { name: :XYZZY,            class: ServiceSkeleton::ConfigVariable::Integer, opts: { default: 42 } },
        { name: :SPEC_SERVICE_VAR, class: ServiceSkeleton::ConfigVariable::String,  opts: { default: "ohai!" } },
      ]
    end

    it "defines a method which returns the variable's value" do
      expect(config.xyzzy).to eq(42)
    end

    it "defines a method which allows the variable value to change" do
      expect { config.xyzzy = 31337 }.to_not raise_error
      expect(config.xyzzy).to eq(31337)
    end

    it "defines a method without the service name prefix which returns the variable's value" do
      expect(config.var).to eq("ohai!")
    end
  end

  context "with sensitive variables" do
    let(:vars) do
      [
        { name: :SEKRIT, class: ServiceSkeleton::ConfigVariable::String, opts: { sensitive: true } },
      ]
    end

    it "redacts the variables from the ENV" do
      env = {
        "SEKRIT" => "x",
        "PUBLIC" => "y",
      }

      with_overridden_constant Object, :ENV, env do
        ServiceSkeleton::Config.new(env, svc)

        expect(env).to eq("SEKRIT" => "*SENSITIVE*", "PUBLIC" => "y")
      end
    end

    it "freaks out if it doesn't have the real ENV" do
      expect { ServiceSkeleton::Config.new({ "SEKRIT" => "x" }, svc) }.to raise_error(ServiceSkeleton::Error::CannotSanitizeEnvironmentError)
    end
  end
end
