# frozen_string_literal: true

require_relative "./spec_helper"
require_relative "./spec_service"

require "service_skeleton"

describe ServiceSkeleton do
  describe "#metrics" do
    let(:svc) { SpecService.new({}) }

    it "allows registration of a counter" do
      expect { svc.metrics.counter(:ohai, "Say hi!") }.to_not raise_error
    end

    it "allows registration of a gauge" do
      expect { svc.metrics.gauge(:ohai, "Say hi!") }.to_not raise_error
    end

    it "allows registration of a histogram" do
      expect { svc.metrics.histogram(:ohai, "Say hi!") }.to_not raise_error
    end

    it "allows registration of a summary" do
      expect { svc.metrics.summary(:ohai, "Say hi!") }.to_not raise_error
    end

    it "allows registration of an arbitrary metric" do
      expect { svc.metrics.register(Prometheus::Client::Counter.new(:ohai, "Say hi!")) }.to_not raise_error
    end

    it "defines a matching method on the metrics object" do
      svc.metrics.register(Prometheus::Client::Counter.new(:ohai, "Say hi!"))

      expect { svc.metrics.ohai.increment }.to_not raise_error
    end

    it "defines a service_name-less matching method on the metrics object" do
      svc.metrics.register(Prometheus::Client::Counter.new(:spec_service_ohai, "Say hi!"))

      expect { svc.metrics.ohai.increment }.to_not raise_error
    end

    it "freaks out if you try to define a method that already exists" do
      expect { svc.metrics.counter(:counter, "Not a good metric name") }.to raise_error(ServiceSkeleton::Error::InvalidMetricNameError)
    end

    it "includes Ruby GC metrics" do
      expect(svc.metrics.get(:ruby_gc_count)).to be_a(Frankenstein::CollectedMetric)
    end

    it "includes Ruby VM metrics" do
      expect(svc.metrics.get(:ruby_vm_class_serial)).to be_a(Frankenstein::CollectedMetric)
    end

    it "includes process metrics" do
      expect(svc.metrics.get(:process_start_time_seconds)).to be_a(Prometheus::Client::Gauge)
    end

    it "does not register the default metrics as methods" do
      %i{ruby_gc_count ruby_vm_class_serial process_start_time_seconds}.each do |m|
        expect(svc.metrics.methods).to_not include(m)
      end
    end
  end
end
