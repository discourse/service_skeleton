# frozen_string_literal: true

require_relative "./spec_helper"

require "service_skeleton/config_variable"

describe ServiceSkeleton::ConfigVariable do
  let(:opts) { {} }

  subject { described_class.new(:FOO, **opts) { 42 } }

  it "accepts a name and a proc" do
    expect { described_class.new(:FOO) {} }.to_not raise_error
  end

  describe "#name" do
    it "returns the variable's name" do
      expect(subject.name).to eq(:FOO)
    end
  end

  describe "#method_name" do
    context "for a variable that does not match the service name" do
      it "returns the downcased variable name" do
        expect(subject.method_name("my_svc")).to eq("foo")
      end
    end

    context "for a variable which starts with the service name" do
      subject { described_class.new(:MY_SVC_FOO) { 42 } }

      it "returns the variable name with the prefix stripped" do
        expect(subject.method_name("my_svc")).to eq("foo")
      end
    end
  end

  describe "#sensitive?" do
    it "is false by default" do
      expect(subject.sensitive?).to eq(false)
    end

    context "when the variable was marked sensitive" do
      let(:opts) { { sensitive: true } }

      it "is true" do
        expect(subject.sensitive?).to eq(true)
      end
    end
  end

  describe "#value" do
    it "calls the underlying proc" do
      expect(subject.value("a")).to eq(42)
    end
  end
end
