# frozen_string_literal: true

require_relative "./spec_helper"
require_relative "./spec_service"

require "service_skeleton"

describe ServiceSkeleton do
  uses_logger

  let(:metrics) { instance_double(Prometheus::Client::Registry) }
  let(:config)  { instance_double(ServiceSkeleton::Config) }

  before(:each) do
    allow(config).to receive(:logger).and_return(logger)
  end

  let(:svc) { SpecService.new(metrics: metrics, config: config) }

  it "can be included" do
    expect { class SpecService; include ServiceSkeleton; end }.to_not raise_error
  end

  describe ".service_name" do
    it "calculates the service name from the class name" do
      expect(SpecService.service_name).to eq("spec_service")
    end

    it "safely handles an anonymous class" do
      klass = Class.new
      klass.include ServiceSkeleton

      expect(klass.service_name).to match(/class_0x\h+/)
    end
  end

  describe "#config" do
    it "returns the provided config" do
      expect(svc.config).to eq(config)
    end
  end

  describe "#logger" do
    it "returns a logger" do
      expect(svc.logger).to be_a(Logger)
    end
  end

  describe "#metrics" do
    it "returns the provided metrics registry" do
      expect(svc.metrics).to eq(metrics)
    end
  end

  describe ".hook_signal" do
    let(:svc_class) do
      Class.new.tap do |klass|
        klass.include ServiceSkeleton
      end
    end

    it "adds a spec to the signal registry" do
      svc_class.hook_signal("CONT") { true }

      expect(svc_class.registered_signal_handlers).to include(["CONT", instance_of(Proc)])
    end
  end
end
