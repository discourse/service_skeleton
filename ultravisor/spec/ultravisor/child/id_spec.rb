# frozen_string_literal: true

require_relative "../../spec_helper"

require "ultravisor/child"
require "ultravisor/error"

describe Ultravisor::Child do
	let(:child) { Ultravisor::Child.new(**args) }
	let(:mock_class) { Class.new.tap { |k| k.class_eval { def run; end } } }

	describe  "#id" do
		context "with minimal arguments" do
			let(:args) { { id: :bob, klass: mock_class, method: :run } }

			it "returns the child's ID" do
				expect(child.id).to eq(:bob)
			end
		end
	end
end

