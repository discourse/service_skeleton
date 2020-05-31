# frozen_string_literal: true

require_relative "../../spec_helper"

require "ultravisor/child"
require "ultravisor/error"

describe Ultravisor::Child do
	uses_logger

	let(:base_args) { { id: :bob, klass: mock_class, method: :run } }
	let(:child) { Ultravisor::Child.new(**args) }
	let(:mock_class) { Class.new.tap { |k| k.class_eval { def run; end; def sigterm; end } } }
	let(:mock_instance) { instance_double(mock_class) }
	let(:term_queue) { instance_double(Queue) }

	describe "#shutdown" do
		let(:args) { base_args }

		context "when the child isn't running" do
			it "returns immediately" do
				child.shutdown
			end
		end

		context "when the child is running" do
			before(:each) do
				orig_thread_new = Thread.method(:new)
				allow(Thread).to receive(:new) do |&b|
					orig_thread_new.call(&b).tap do |th|
						@thread = th
						allow(th).to receive(:kill).and_call_original
						allow(th).to receive(:join).and_call_original
					end
				end

				allow(mock_class).to receive(:new).and_return(mock_instance)
				allow(mock_instance).to receive(:run)

				allow(term_queue).to receive(:<<)
			end

			it "kills the thread" do
				child.spawn(term_queue).shutdown

				expect(@thread).to have_received(:kill)
			end

			it "waits for the thread to be done" do
				child.spawn(term_queue).shutdown

				expect(@thread).to have_received(:join).with(1)
			end

			it "doesn't put anything on the queue" do
				expect(term_queue).to_not receive(:<<)

				child.spawn(term_queue).shutdown
			end

			context "when there's a shutdown spec" do
				let(:args) { base_args.merge(shutdown: { method: :sigterm, timeout: 0.05 }) }

				before(:each) do
					allow(mock_instance).to receive(:sigterm)
				end

				it "calls the specified shutdown method" do
					expect(mock_instance).to receive(:sigterm)

					child.spawn(term_queue).shutdown
				end

				it "waits for up to the timeout period" do
					child.spawn(term_queue).shutdown

					expect(@thread).to have_received(:join).with(0.05)
				end

				context "the worker doesn't finish quickly enough" do
					before(:each) do
						allow(mock_instance).to receive(:run) { sleep 15 }
					end

					it "kills the thread" do
						child.spawn(term_queue).shutdown

						expect(@thread).to have_received(:kill)
					end
				end
			end

			context "when the thread infinihangs" do
				# No need for a big timeout, we know it's not going to succeed
				let(:args) { base_args.merge(shutdown: { timeout: 0.000001 }) }
				let(:m) { Mutex.new }
				let(:cv) { ConditionVariable.new }

				before(:each) do
					allow(mock_instance).to receive(:run) do
						Thread.handle_interrupt(Numeric => :never) do
							m.synchronize do
								@state = 1
								cv.signal
								cv.wait(m) until @state == 2
							end
						end
					end

					allow(logger).to receive(:error)
				end

				it "logs an error" do
					expect(logger).to receive(:error)

					child.spawn(term_queue)
					m.synchronize { cv.wait(m) until @state == 1 }
					child.shutdown
					m.synchronize { @state = 2; cv.signal }
				end
			end
		end
	end
end
