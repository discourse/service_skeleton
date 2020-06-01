# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "../../spec_service"

require "service_skeleton"

describe ServiceSkeleton do
  describe "#metrics" do
    let(:svc) { SpecService }

    it "allows registration of a counter" do
      expect { svc.counter(:ohai, docstring: "Say hi!") }.to_not raise_error
    end

    it "allows registration of a gauge" do
      expect { svc.gauge(:ohai, docstring: "Say hi!") }.to_not raise_error
    end

    it "allows registration of a histogram" do
      expect { svc.histogram(:ohai, docstring: "Say hi!") }.to_not raise_error
    end

    it "allows registration of a summary" do
      expect { svc.summary(:ohai, docstring: "Say hi!") }.to_not raise_error
    end

    it "allows registration of an arbitrary metric" do
      expect { svc.metric(Prometheus::Client::Counter.new(:ohai, docstring: "Say hi!")) }.to_not raise_error
    end
  end
end
