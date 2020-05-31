# frozen_string_literal: true

require_relative "../spec_helper"
require_relative "../spec_service"

require "service_skeleton"

describe ServiceSkeleton do
  describe "#metrics" do
    let(:svc_class) do
      Class.new do |k|
        ::MeasuredService = k
        Object.__send__(:remove_const, :MeasuredService)

        k.include ServiceSkeleton
      end
    end

    let(:registry) { Prometheus::Client::Registry.new }
    let(:config)   { ServiceSkeleton::Config.new({}, "", []) }
    let(:svc)      { svc_class.new(metrics: registry, config: config) }

    it "returns the registry we passed in" do
      expect(svc.metrics).to be(registry)
    end
  end
end
