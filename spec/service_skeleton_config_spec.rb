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
        .to eq("W [Spec] ohai!\n")
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
          .to eq("2009-02-13T23:31:30.987654321Z I [Stamped] ohai!\n")
      end
    end

    context "with LOG_FILE specified" do
      let(:env) { { "SPEC_SERVICE_LOG_FILE" => "/var/log/spec_service.log" } }

      it "configures the logger appropriately" do
        expect(Logger::LogDevice).to receive(:new).with("/var/log/spec_service.log", shift_age: 3, shift_size: 1048576)

        config
      end
    end

    context "with LOG_MAX_FILE_SIZE specified" do
      let(:env) { { "SPEC_SERVICE_LOG_MAX_FILE_SIZE" => "1234567" } }

      it "configures the logger appropriately" do
        expect(Logger::LogDevice).to receive(:new).with($stderr, shift_age: 3, shift_size: 1234567)

        config
      end
    end

    context "with LOG_MAX_FILE_SIZE=0" do
      let(:env) { { "SPEC_SERVICE_LOG_MAX_FILE_SIZE" => "0" } }

      it "configures the logger appropriately" do
        expect(Logger::LogDevice).to receive(:new).with($stderr, shift_age: 0, shift_size: 0)

        config
      end
    end

    context "with LOG_MAX_FILES specified" do
      let(:env) { { "SPEC_SERVICE_LOG_MAX_FILES" => "42" } }

      it "configures the logger appropriately" do
        expect(Logger::LogDevice).to receive(:new).with($stderr, shift_age: 42, shift_size: 1048576)

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
        ServiceSkeleton::ConfigVariable.new(:XYZZY) { 42 },
        ServiceSkeleton::ConfigVariable.new(:SPEC_SERVICE_VAR) { "ohai!" },
      ]
    end

    it "defines a method which returns the variable's value" do
      expect(config.xyzzy).to eq(42)
    end

    it "defines a method without the service name prefix which returns the variable's value" do
      expect(config.var).to eq("ohai!")
    end
  end

  context "with sensitive variables" do
    let(:vars) do
      [
        ServiceSkeleton::ConfigVariable.new(:SEKRIT, sensitive: true) { "password1!" },
      ]
    end

    it "deletes the variable from the ENV" do
      env = {
        "SEKRIT" => "x",
        "PUBLIC" => "y",
      }

      with_overridden_constant Object, :ENV, env do
        ServiceSkeleton::Config.new(env, svc)
      end

      expect(env).to eq("PUBLIC" => "y")
    end

    it "freaks out if it doesn't have the real ENV" do
      expect { ServiceSkeleton::Config.new({}, svc) }.to raise_error(ServiceSkeleton::Error::CannotSanitizeEnvironmentError)
    end
  end
end