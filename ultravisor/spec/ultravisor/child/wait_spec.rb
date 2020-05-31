# frozen_string_literal: true

require_relative "../../spec_helper"

require "ultravisor/child"
require "ultravisor/error"

describe Ultravisor::Child do
	let(:args) { { id: :bob, klass: mock_class, method: :run } }
	let(:child) { Ultravisor::Child.new(**args) }
	let(:mock_class) { Class.new.tap { |k| k.class_eval { def run; end } } }

	describe "#wait" do
		context "when the child isn't running" do
			it "just returns straight away" do
				child.wait
			end
		end

		context "when the child is running" do
			it "only exits once the child has finished" do
				child.instance_variable_set(:@thread, Thread.new {})

				expect(child.instance_variable_get(:@spawn_cv)).to receive(:wait).with(child.instance_variable_get(:@spawn_m)) do
					child.instance_variable_set(:@thread, nil)
				end

				child.wait
			end
		end
	end
end

