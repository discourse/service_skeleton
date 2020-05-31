# frozen_string_literal: true

require_relative "../../spec_helper"

require "ultravisor/child"
require "ultravisor/error"

class CastCallTest
	def run
	end

	def poke_processor
		process_castcall
	end
end

describe Ultravisor::Child do
	let(:child) { Ultravisor::Child.new(**args) }
	let(:instance) { child.__send__(:new_instance) }

	describe "#cast" do
		context "without enable_castcall" do
			let(:args) do
				{
					id: :cast_child,
					klass: CastCallTest,
					method: :run,
				}
			end

			it "does not accept calls to #cast" do
				expect { child.cast }.to raise_error(NoMethodError)
			end
		end

		context "with enable_castcall" do
			let(:args) do
				{
					id: :cast_child,
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
			end

			it "accepts calls to #cast" do
				expect { child.cast }.to_not raise_error
			end

			it "does not accept cast calls to methods that do not exist on the worker object" do
				expect { child.cast.flibbetygibbets }.to raise_error(NoMethodError)
			end

			it "does not accept cast calls to private methods on the worker object" do
				expect { child.cast.eval }.to raise_error(NoMethodError)
			end

			it "accepts calls to methods that exist on the worker object" do
				expect { child.cast.to_s }.to_not raise_error
			end

			it "calls the instance method only when process_castcall is called" do
				child.cast.to_s
				expect(instance).to_not have_received(:to_s)
				instance.poke_processor
				expect(instance).to have_received(:to_s)
			end

			it "processes all the queued method calls" do
				child.cast.to_s
				child.cast.to_s
				child.cast.to_s
				child.cast.to_s
				child.cast.to_s
				expect(instance).to_not have_received(:to_s)
				instance.poke_processor
				expect(instance).to have_received(:to_s).exactly(5).times
			end

			let(:cc_fd) { instance.__send__(:castcall_fd) }
			it "marks the castcall_fd as readable only after cast is called" do
				expect(IO.select([cc_fd], nil, nil, 0)).to eq(nil)

				child.cast.to_s

				expect(IO.select([cc_fd], nil, nil, 0)).to eq([[cc_fd], [], []])
			end

			it "does not have a readable castcall_fd after process_castcall" do
				child.cast.to_s
				expect(IO.select([cc_fd], nil, nil, 0)).to eq([[cc_fd], [], []])
				instance.poke_processor
				expect(IO.select([cc_fd], nil, nil, 0)).to eq(nil)
			end

			it "does not explode if the instance is dying" do
				instance.instance_variable_get(:@ultravisor_child_castcall_queue).close

				expect { child.cast.to_s }.to_not raise_error
			end
		end
	end
end

