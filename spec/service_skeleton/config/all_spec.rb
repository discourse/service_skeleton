# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "../../spec_service"

require "service_skeleton"
require "service_skeleton/config"
require "service_skeleton/error"

describe ServiceSkeleton::Config do
  let(:env)          { {} }
  let(:service_name) { "SPEC_SERVICE" }
  let(:variables)    { [] }
  let(:config)       { ServiceSkeleton::Config.new(env, service_name, variables) }

  describe "#logger" do
    it "returns a logger" do
      expect(config.logger).to be_a(Logger)
    end

    it "logs to stderr" do
      expect(Logger).to receive(:new).twice.with($stderr, 3, 1048576).and_call_original
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
        expect(Logger::LogDevice).to receive(:new).twice.with("/var/log/spec_service.log", include(shift_age: 3, shift_size: 1048576))

        config
      end
    end

    context "with LOG_MAX_FILE_SIZE specified" do
      let(:env) { { "SPEC_SERVICE_LOG_MAX_FILE_SIZE" => "1234567" } }

      it "configures the logger appropriately" do
        expect(Logger::LogDevice).to receive(:new).twice.with($stderr, include(shift_age: 3, shift_size: 1234567))

        config
      end
    end

    context "with LOG_MAX_FILE_SIZE=0" do
      let(:env) { { "SPEC_SERVICE_LOG_MAX_FILE_SIZE" => "0" } }

      it "configures the logger appropriately" do
        expect(Logger::LogDevice).to receive(:new).twice.with($stderr, include(shift_age: 0, shift_size: 0))

        config
      end
    end

    context "with LOG_MAX_FILES specified" do
      let(:env) { { "SPEC_SERVICE_LOG_MAX_FILES" => "42" } }

      it "configures the logger appropriately" do
        expect(Logger::LogDevice).to receive(:new).twice.with($stderr, include(shift_age: 42, shift_size: 1048576))

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
    let(:svc_class) do
      Class.new do |k|
        # This is an annoyingly roundabout way of naming a class
        ::DvService = k
        Object.__send__(:remove_const, :DvService)

        k.include ServiceSkeleton
        k.integer :XYZZY,          default: 42
        k.string  :DV_SERVICE_VAR, default: "ohai!"
      end
    end
    let(:service_name) { svc_class.service_name }
    let(:variables)    { svc_class.registered_variables }

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
    let(:env) do
      {
        "SEKRIT" => "x",
        "PUBLIC" => "y",
      }
    end
    let(:variables) { [{ class: ServiceSkeleton::ConfigVariable::String, name: "SEKRIT", opts: { sensitive: true } }] }

    it "redacts the variables from the ENV" do
      with_overridden_constant Object, :ENV, env do
        config

        expect(env).to eq("SEKRIT" => "*SENSITIVE*", "PUBLIC" => "y")
      end
    end

    it "freaks out if it doesn't have the real ENV" do
      expect { config }.to raise_error(ServiceSkeleton::Error::CannotSanitizeEnvironmentError)
    end
  end
end
