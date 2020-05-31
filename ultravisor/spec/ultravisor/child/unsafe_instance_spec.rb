# frozen_string_literal: true

require_relative "../../spec_helper"

require "ultravisor/child"
require "ultravisor/error"

describe Ultravisor::Child do
	let(:args) { { id: :bob, klass: Object, method: :to_s } }
	let(:child) { Ultravisor::Child.new(**args) }

	describe "#unsafe_instance" do
		context "by default" do
			it "explodes" do
				expect { child.unsafe_instance }.to raise_error(Ultravisor::ThreadSafetyError)
			end
		end

		context "with access: :unsafe" do
			let(:args) { { id: :bob, klass: Object, method: :to_s, access: :unsafe } }

			context "when there's no instance object" do
				it "waits for the instance object to appear" do
					expect(child.instance_variable_get(:@spawn_cv)).to receive(:wait) do
						child.instance_variable_set(:@instance, "gogogo")
					end

					child.unsafe_instance
				end
			end

			context "when there's an instance object" do
				before(:each) do
					child.instance_variable_set(:@instance, "bob")
				end

				it "returns the instance object" do
					expect(child.unsafe_instance).to eq("bob")
				end
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

