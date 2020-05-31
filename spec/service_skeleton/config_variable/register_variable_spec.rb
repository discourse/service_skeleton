# frozen_string_literal: true

require_relative "../../spec_helper"

require "service_skeleton"

describe ServiceSkeleton::ConfigVariables do
  let(:klass) { Class.new.include(ServiceSkeleton) }

  describe "#register_variable" do
    it "inserts a simple variable registration into the variable registry" do
      klass.register_variable(:XYZZY, ServiceSkeleton::ConfigVariable::String)

      expect(klass.registered_variables).to include(name: :XYZZY, class: ServiceSkeleton::ConfigVariable::String, opts: {})
    end

    it "inserts a default-value variable registration into the variable registry" do
      klass.register_variable(:XYZZY, ServiceSkeleton::ConfigVariable::String, default: "42")

      expect(klass.registered_variables).to include(name: :XYZZY, class: ServiceSkeleton::ConfigVariable::String, opts: { default: "42" })
    end

    it "inserts an arbitrary-opts variable registration into the variable registry" do
      klass.register_variable(:XYZZY, ServiceSkeleton::ConfigVariable::String, something: "funny")

      expect(klass.registered_variables).to include(name: :XYZZY, class: ServiceSkeleton::ConfigVariable::String, opts: { something: "funny" })
    end
  end
end
