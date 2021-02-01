# frozen_string_literal: true

require_relative "../../spec_helper"

require_relative "../../../lib/ultravisor/child"
require_relative "../../../lib/ultravisor/error"

class CastCallTest
  class FakeError < RuntimeError; end

  def run
  end

  def poke_processor
    process_castcall
  end

  def failing_method
    raise FakeError
  end
end

describe Ultravisor::Child do
  let(:child) { Ultravisor::Child.new(**args) }
  let(:instance) { child.__send__(:new_instance) }

  describe "#call" do
    context "without enable_castcall" do
      let(:args) do
        {
          id: :call_child,
          klass: CastCallTest,
          method: :run,
        }
      end

      it "does not accept calls to #call" do
        expect { child.call }.to raise_error(NoMethodError)
      end
    end

    context "with enable_castcall" do
      let(:args) do
        {
          id: :call_child,
          klass: CastCallTest,
          method: :run,
          enable_castcall: true,
        }
      end

      before(:each) do
        # Got to have an instance otherwise all hell breaks loose
        child.instance_variable_set(:@instance, instance)

        # So we can check if and when it's been called
        allow(instance).to receive(:to_s).and_call_original
        allow(instance).to receive(:failing_method).and_call_original
      end

      it "accepts calls to #call" do
        expect { child.call }.to_not raise_error
      end

      it "does not accept call calls to methods that do not exist on the worker object" do
        expect { child.call.flibbetygibbets }.to raise_error(NoMethodError)
      end

      it "does not accept call calls to private methods on the worker object" do
        expect { child.call.eval }.to raise_error(NoMethodError)
      end

      it "accepts calls to methods that exist on the worker object" do
        th = Thread.new { child.call.to_s }
        th.join(0.01)
        instance.poke_processor
        expect { th.value }.to_not raise_error
      end

      it "calls the instance method only when process_castcall is called" do
        th = Thread.new { child.call.to_s }
        th.join(0.001)

        # Thread should be ticking along, not dead
        expect(th.status).to eq("sleep")
        expect(instance).to_not have_received(:to_s)
        instance.poke_processor
        expect(instance).to have_received(:to_s)
        expect(th.value).to be_a(String)
      end

      it "raises a relevant error if the call itself causes an exception is dying" do
        th = Thread.new { child.call.failing_method }
        th.join(0.001)

        expect(instance).to_not have_received(:failing_method)
        expect { instance.poke_processor }.to raise_error(CastCallTest::FakeError)
        expect(instance).to have_received(:failing_method)

        expect { th.value }.to raise_error(Ultravisor::ChildRestartedError)
      end

      it "raises a relevant error if the instance is dying" do
        instance.instance_variable_get(:@ultravisor_child_castcall_queue).close

        expect { child.call.to_s }.to raise_error(Ultravisor::ChildRestartedError)
      end

      it "raises an error to all incomplete calls if the instance terminates" do
        th = Thread.new { child.call.to_s }

        th.join(0.001) until th.status == "sleep"

        expect(instance).to_not have_received(:to_s)
        child.instance_variable_get(:@spawn_m).synchronize { child.__send__(:termination_cleanup) }

        expect { th.value }.to raise_error(Ultravisor::ChildRestartedError)
      end
    end
  end
end
