# frozen_string_literal: true

require_relative "../../spec_helper"

require "ultravisor/child"
require "ultravisor/error"

describe Ultravisor::Child do
	let(:base_args) { { id: :bob, klass: Object, method: :to_s } }
	let(:child) { Ultravisor::Child.new(**args) }

	describe "#restart?" do
		context "when restart: :always" do
			# Yes, this is the default, but I do like to be explicit
			let(:args) { base_args.merge(restart: :always) }

			it "is true always" do
				expect(child.restart?).to be(true)
			end
		end

		context "when restart: :never" do
			let(:args) { base_args.merge(restart: :never) }

			it "is false always" do
				expect(child.restart?).to be(false)
			end
		end

		context "when restart: :on_failure" do
			let(:args) { base_args.merge(restart: :on_failure) }

			it "is true if the child terminated with an exception" do
				expect(child).to receive(:termination_exception).and_return(Exception.new("boom"))

				expect(child.restart?).to be(true)
			end

			it "is false if the child didn't terminate with an exception" do
				expect(child).to receive(:termination_exception).and_return(nil)

				expect(child.restart?).to be(false)
			end
		end

		context "with a restart history that isn't blown" do
			let(:args) { base_args.merge(restart: :always, restart_policy: { period: 10, max: 3 }) }

			before(:each) do
				child.instance_variable_set(:@runtime_history, [4.99, 4.99, 4.99])
			end

			it "still returns true" do
				expect(child.restart?).to be(true)
			end
		end

		context "with a restart history that is blown" do
			let(:args) { base_args.merge(restart: :always, restart_policy: { period: 10, max: 2 }) }

			before(:each) do
				child.instance_variable_set(:@runtime_history, [4.99, 4.99, 4.99])
			end

			it "explodes" do
				expect { child.restart? }.to raise_error(Ultravisor::BlownRestartPolicyError)
			end
		end
	end
end

