require_relative "../spec_helper"

require "ultravisor"

describe Ultravisor do
	let(:args) { {} }
	let(:ultravisor) { Ultravisor.new(**args) }
	let!(:child) { Ultravisor::Child.new(id: :xtra, klass: Class, method: :to_s) }

	describe "#add_child" do
		before(:each) do
			allow(Ultravisor::Child).to receive(:new).and_return(child)
		end

		context "when the ultravisor isn't running" do
			it "creates a new Child object" do
				expect(Ultravisor::Child).to receive(:new).with(id: :xtra, klass: Class, method: :to_s)

				ultravisor.add_child(id: :xtra, klass: Class, method: :to_s)
			end

			it "registers the new child" do
				ultravisor.add_child(id: :xtra, klass: Class, method: :to_s)

				expect(ultravisor[:xtra]).to be_a(Ultravisor::Child)
			end

			it "explodes if a dupe child ID is used" do
				ultravisor.add_child(id: :xtra, klass: Class, method: :to_s)

				expect do
					ultravisor.add_child(id: :xtra, klass: Object, method: :to_s)
				end.to raise_error(Ultravisor::DuplicateChildError)
			end

			it "doesn't spawn a child thread" do
				expect(child).to_not receive(:spawn)

				ultravisor.add_child(id: :xtra, klass: Class, method: :to_s)
			end
		end

		context "while the ultravisor *is* running" do
			let(:mock_thread) { instance_double(Thread) }

			before(:each) do
				allow(child).to receive(:spawn)
				ultravisor.instance_variable_set(:@running_thread, mock_thread)
			end

			it "creates a new Child object" do
				expect(Ultravisor::Child).to receive(:new).with(id: :xtra, klass: Class, method: :to_s)

				ultravisor.add_child(id: :xtra, klass: Class, method: :to_s)
			end

			it "registers the new child" do
				ultravisor.add_child(id: :xtra, klass: Class, method: :to_s)

				expect(ultravisor[:xtra]).to be_a(Ultravisor::Child)
			end

			it "explodes if a dupe child ID is used" do
				ultravisor.add_child(id: :xtra, klass: Class, method: :to_s)

				expect do
					ultravisor.add_child(id: :xtra, klass: Object, method: :to_s)
				end.to raise_error(Ultravisor::DuplicateChildError)
			end

			it "spawns a child thread" do
				ultravisor.add_child(id: :xtra, klass: Class, method: :to_s)

				expect(child).to have_received(:spawn)
			end
		end
	end
end
