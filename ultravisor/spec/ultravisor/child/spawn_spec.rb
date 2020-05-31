# frozen_string_literal: true

require_relative "../../spec_helper"

require "ultravisor/child"
require "ultravisor/error"

describe Ultravisor::Child do
	let(:child) { Ultravisor::Child.new(**args) }
	let(:mock_class) { Class.new.tap { |k| k.class_eval { def run; end } } }
	let(:mock_instance) { double(mock_class) }
	let(:term_queue) { instance_double(Queue) }

	describe "#spawn" do
		before(:each) do
			allow(term_queue).to receive(:<<)
		end

		context "with minimal arguments" do
			let(:args) { { id: :bob, klass: mock_class, method: :run } }

			before(:each) do
				allow(mock_class).to receive(:new).and_return(mock_instance)
				allow(mock_instance).to receive(:run)
			end

			it "instantiates the class" do
				expect(mock_class).to receive(:new).with(no_args)

				child.spawn(term_queue).wait
			end

			it "calls the run method on the class instance" do
				expect(mock_instance).to receive(:run).with(no_args)

				child.spawn(term_queue).wait
			end

			it "registers the thread it is running in" do
				expect(mock_instance).to receive(:run) do
					expect(child.instance_variable_get(:@thread)).to eq(Thread.current)
				end

				child.spawn(term_queue).wait
			end

			it "notes the start time" do
				expect(mock_instance).to receive(:run) do
					# Can only check @start_time while the child is running, as the
					# variable gets nil'd after the run completes
					expect(child.instance_variable_get(:@start_time).to_f).to be_within(0.01).of(Time.now.to_f)
				end

				child.spawn(term_queue).wait
			end

			it "notes the termination value" do
				expect(mock_instance).to receive(:run).with(no_args).and_return(42)

				child.spawn(term_queue)

				expect(child.termination_value).to eq(42)
			end

			it "tells the ultravisor it terminated" do
				expect(term_queue).to receive(:<<).with(child)

				child.spawn(term_queue).wait
			end

			it "creates a new thread" do
				expect(Thread).to receive(:new)

				child.spawn(term_queue).wait
			end

			context "when the worker object's run method raises an exception" do
				before(:each) do
					allow(mock_instance).to receive(:run).and_raise(RuntimeError.new("FWACKOOM"))
				end

				it "makes a note of the exception" do
					child.spawn(term_queue)

					expect(child.termination_exception).to be_a(RuntimeError)
				end

				it "tells the ultravisor it terminated" do
					expect(term_queue).to receive(:<<).with(child)

					child.spawn(term_queue).wait
				end
			end
		end

		context "with a worker class that takes args" do
			let(:args) { { id: :testy, klass: mock_class, args: ["foo", "bar", baz: "wombat"], method: :run } }
			let(:mock_class) { Class.new.tap { |k| k.class_eval { def initialize(*x); end; def run; end } } }

			it "creates the class instance with args" do
				expect(mock_class).to receive(:new).with("foo", "bar", baz: "wombat").and_call_original

				child.spawn(term_queue).wait
			end
		end
	end
end
