# frozen_string_literal: true

require_relative "../../spec_helper"

require "ultravisor/child"

describe Ultravisor::Child do
	let(:base_args) { { id: :bob, klass: mock_class, method: :run } }
	let(:child) { Ultravisor::Child.new(**args) }
	let(:mock_class) { Class.new.tap { |k| k.class_eval { def run; end } } }

	describe "#restart_delay" do
		context "by default" do
			let(:args) { base_args }

			it "returns the default delay" do
				expect(child.restart_delay).to eq(1)
			end
		end

		context "with a specified numeric delay" do
			let(:args) { base_args.merge(restart_policy: { delay: 3.14159 }) }

			it "returns the specified delay" do
				expect(child.restart_delay).to be_within(0.00001).of(3.14159)
			end
		end

		context "with a delay range" do
			let(:args) { base_args.merge(restart_policy: { delay: 2..5 }) }

			it "returns a delay in the given range" do
				delays = 10.times.map { child.restart_delay }

				expect(delays.all? { |d| (2..5).include?(d) }).to be(true)
				expect(delays.uniq.length).to eq(10)
			end
		end
	end
end

