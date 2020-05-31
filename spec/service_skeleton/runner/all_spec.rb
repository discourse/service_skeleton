# frozen_string_literal: true

require_relative "../../spec_helper"

require "service_skeleton"

describe ServiceSkeleton::Runner do
  uses_logger

  let(:svc_class) { Class.new.tap { |k| k.include(ServiceSkeleton) } }
  let(:env)       { {} }
  let(:runner)    { ServiceSkeleton::Runner.new(svc_class, env) }

  let(:ultravisor) { instance_double(Ultravisor) }

  before(:each) do
    allow(Ultravisor).to receive(:new).and_return(ultravisor)
    allow(ultravisor).to receive(:add_child)
  end

  describe "#initialize" do
    it "instantiates a ServiceSkeleton::Config instance" do
      expect(ServiceSkeleton::Config).to receive(:new).and_call_original

      runner
    end

    context "with a custom config_class" do
      let(:config_class) { Class.new(ServiceSkeleton::Config) }
      let(:svc_class) do
        Class.new.tap do |k|
          k.include(ServiceSkeleton)
          k.config_class(config_class)
        end
      end

      it "instantiates the custom config class" do
        expect(config_class).to receive(:new).and_call_original

        runner
      end
    end

    it "fails if the class doesn't have a :run method" do
      expect(ultravisor)
        .to receive(:add_child)
        .with(include(id: svc_class.service_name.to_sym))
        .and_raise(Ultravisor::InvalidKAMError)

      expect { runner }.to raise_error(ServiceSkeleton::Error::InvalidServiceClassError)
    end
  end

  describe "#run" do
    before(:each) do
      allow(ultravisor).to receive(:run)
    end

    it "fires off the Ultravisor" do
      expect(ultravisor).to receive(:run)

      runner.run
    end
  end
end
