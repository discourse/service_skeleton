require_relative "../spec_helper"

require "ultravisor"

describe Ultravisor do
	let(:args) { {} }
	let(:ultravisor) { Ultravisor.new(**args) }
	let(:mock_child) { instance_double(Ultravisor::Child) }

	describe "#remove_child" do
		before(:each) do
			ultravisor.instance_variable_set(:@children, [[:lamb, mock_child]])
		end

		context "when the ultravisor isn't running" do
			it "removes the child from the list of children" do
				ultravisor.remove_child(:lamb)

				expect(ultravisor[:lamb]).to be(nil)
			end

			it "doesn't explode if asked to remove a child that doesn't exist" do
				expect { ultravisor.remove_child(:no_such_child) }.to_not raise_error
			end
		end

		context "while the ultravisor is running" do
			let(:mock_thread) { instance_double(Thread) }

			before(:each) do
				allow(mock_child).to receive(:shutdown)
				ultravisor.instance_variable_set(:@running_thread, mock_thread)
			end

			it "shuts down the child" do
				expect(mock_child).to receive(:shutdown)

				ultravisor.remove_child(:lamb)
			end

			it "removes the child from the list of children" do
				ultravisor.remove_child(:lamb)

				expect(ultravisor[:lamb]).to be(nil)
			end
		end
	end
end
