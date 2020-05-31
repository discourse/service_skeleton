require_relative "../spec_helper"

require "ultravisor"

describe Ultravisor do
	describe ".new" do
		context "without arguments" do
			it "does not explode" do
				expect { Ultravisor.new }.to_not raise_error
			end

			it "gives us an Ultravisor instance" do
				expect(Ultravisor.new).to be_a(Ultravisor)
			end
		end

		context "with empty children" do
			it "does not explode" do
				expect { Ultravisor.new children: [] }.to_not raise_error
			end
		end

		context "with children that isn't an array" do
			it "raises an error" do
				[{}, "ohai!", nil, 42].each do |v|
					expect { Ultravisor.new children: v }.to raise_error(ArgumentError)
				end
			end
		end

		context "with valid children" do
			let(:ultravisor) { Ultravisor.new(children: [{ id: :testy, klass: Object, method: :to_s }]) }

			it "registers the child by its ID" do
				expect(ultravisor[:testy]).to be_a(Ultravisor::Child)
			end
		end

		context "with two children with the same ID" do
			it "explodes" do
				expect do
					Ultravisor.new(
						children: [
							{ id: :testy, klass: Object, method: :to_s },
							{ id: :testy, klass: Class, method: :to_s },
						]
					)
				end.to raise_error(Ultravisor::DuplicateChildError)
			end
		end

		context "with a valid strategy" do
			it "does not explode" do
				expect { Ultravisor.new strategy: :all_for_one }.to_not raise_error
			end
		end

		[
			{ strategy: :bob },
			{ strategy: "all_for_one" },
			{ strategy: ["games"] },
		].each do |s|
			context "with invalid strategy #{s.inspect}" do
				it "explodes" do
					expect { Ultravisor.new **s }.to raise_error(ArgumentError)
				end
			end
		end
	end
end
