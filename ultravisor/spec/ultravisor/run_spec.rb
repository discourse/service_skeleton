require_relative "../spec_helper"

require "ultravisor"

describe Ultravisor do
	uses_logger

	describe "#run" do
		let(:mock_class) { Class.new.tap { |k| k.class_eval { def run; end } } }
		let(:args) { { children: [{ id: :testy, klass: mock_class, method: :run }] } }
		let(:ultravisor) { Ultravisor.new(**args) }
		let(:mock_thread) { instance_double(Thread) }

		before(:each) do
			allow(ultravisor.instance_variable_get(:@queue)).to receive(:pop).and_return(:shutdown)
		end

		context "with no children" do
			let(:args) { {} }

			it "doesn't start anything" do
				expect(Thread).to_not receive(:new)

				expect { ultravisor.run }.to_not raise_error
			end
		end

		context "when already running" do
			before(:each) do
				ultravisor.instance_variable_set(:@running_thread, mock_thread)
			end

			it "raises an exception" do
				expect { ultravisor.run }.to raise_error(Ultravisor::AlreadyRunningError)
			end
		end

		context "when the event handler gets an unknown event" do
			before(:each) do
				allow(ultravisor.instance_variable_get(:@queue)).to receive(:pop).and_return("wassamatta", :shutdown)
				allow(logger).to receive(:error)
			end

			it "logs an error" do
				expect(logger).to receive(:error).with(match(/^Ultravisor#.*process_events/))

				ultravisor.run
			end
		end

		context "with a single child" do
			let(:child) { Ultravisor::Child.new(id: :testy, klass: Object, method: :to_s) }

			before(:each) do
				allow(child).to receive(:spawn)
				ultravisor.instance_variable_set(:@children, [[child.id, child]])
			end

			it "spawns a child worker" do
				expect(child).to receive(:spawn)

				ultravisor.run
			end

			it "shuts down the child on termination" do
				expect(ultravisor.instance_variable_get(:@children).first.last).to receive(:shutdown)

				ultravisor.run
			end

			context "that terminates" do
				before(:each) do
					allow(ultravisor.instance_variable_get(:@queue)).to receive(:pop).and_return(child, :shutdown)
					allow(ultravisor).to receive(:sleep)
				end

				context "within the limits of its restart policy" do
					it "spawns the child again" do
						expect(child).to receive(:spawn).exactly(:twice)

						ultravisor.run
					end

					it "sleeps between restart" do
						expect(ultravisor).to receive(:sleep).with(1)

						ultravisor.run
					end
				end

				context "too often for its restart policy" do
					before(:each) do
						allow(child).to receive(:restart?).and_raise(Ultravisor::BlownRestartPolicyError)
						allow(logger).to receive(:error)
					end

					it "terminates the ultravisor" do
						expect(ultravisor.instance_variable_get(:@queue)).to receive(:<<).with(:shutdown)

						ultravisor.run
					end

					it "logs an error" do
						expect(logger).to receive(:error)

						ultravisor.run
					end
				end

				context "with a restart_policy delay range" do
					let(:child) { Ultravisor::Child.new(id: :testy, klass: mock_class, method: :run, restart_policy: { delay: 7..12 }) }

					it "sleeps for a period within the range" do
						expect(ultravisor).to receive(:sleep).with(be_between(7, 12))

						ultravisor.run
					end
				end

				context "while we're in the process of shutting down" do
					before(:each) do
						allow(ultravisor.instance_variable_get(:@queue)).to receive(:pop) do
							if ultravisor.instance_variable_get(:@running_thread)
								ultravisor.instance_variable_set(:@running_thread, nil)
								child
							else
								:shutdown
							end
						end
					end

					it "doesn't respawn the child" do
						expect(child).to receive(:spawn).exactly(:once)

						ultravisor.run
					end
				end

				context "with restart: :never" do
					let(:child) { Ultravisor::Child.new(id: :once, klass: mock_class, restart: :never, method: :run) }

					it "doesn't respawn the child" do
						expect(child).to receive(:spawn).exactly(:once)

						ultravisor.run
					end
				end

				context "with restart: :on_failure" do
					let(:child) { Ultravisor::Child.new(id: :once, klass: mock_class, restart: :on_failure, method: :run) }

					it "doesn't respawn the child" do
						expect(child).to receive(:spawn).exactly(:once)

						ultravisor.run
					end
				end

				context "with an error" do
					before(:each) do
						allow(logger).to receive(:error)
						ex = Errno::ENOENT.new("I stiiiiiiiill haven't found, what I'm lookin' for")
						ex.set_backtrace(caller)
						allow(child).to receive(:termination_exception).and_return(ex)
					end

					it "logs the error" do
						expect(logger).to receive(:error).with(match(/:testy/))

						ultravisor.run
					end

					it "respawns the child" do
						expect(child).to receive(:spawn).exactly(:twice)

						ultravisor.run
					end

					context "with restart: :on_failure" do
						let(:child) { Ultravisor::Child.new(id: :once, klass: mock_class, restart: :on_failure, method: :run) }

						it "respawns the child" do
							expect(child).to receive(:spawn).exactly(:twice)

							ultravisor.run
						end
					end
				end
			end
		end

		context "with two children" do
			let(:args) do
				{
					children: [
						{
							id: :one,
							klass: Object,
							method: :to_s,
						},
						{
							id: :two,
							klass: Object,
							method: :to_s,
						}
					]
				}
			end

			it "starts the children in order of their definition" do
				expect(ultravisor[:one]).to receive(:spawn).ordered
				expect(ultravisor[:two]).to receive(:spawn).ordered

				ultravisor.run
			end

			it "shuts the children down in the opposite order" do
				expect(ultravisor[:two]).to receive(:shutdown).ordered
				expect(ultravisor[:one]).to receive(:shutdown).ordered

				ultravisor.run
			end
		end

		context "with an all_for_one strategy" do
			let(:args) do
				{
					strategy: :all_for_one,
					children: [
						{
							id: :one,
							klass: Object,
							method: :to_s,
						},
						{
							id: :two,
							klass: Object,
							method: :to_s,
						},
						{
							id: :three,
							klass: Object,
							method: :to_s,
						},
					]
				}
			end

			let(:child1) { Ultravisor::Child.new(id: :one, klass: Object, method: :to_s) }
			let(:child2) { Ultravisor::Child.new(id: :two, klass: Object, method: :to_s) }
			let(:child3) { Ultravisor::Child.new(id: :three, klass: Object, method: :to_s) }

			before(:each) do
				ultravisor.instance_variable_set(:@children, [[:one, child1], [:two, child2], [:three, child3]])
				allow(ultravisor.instance_variable_get(:@queue)).to receive(:pop).and_return(child2, :shutdown)
				allow(ultravisor).to receive(:sleep)
				ultravisor.instance_variable_set(:@running_thread, mock_thread)
			end

			it "shuts down all the other children in reverse order" do
				expect(child3).to receive(:shutdown).ordered
				expect(child1).to receive(:shutdown).ordered

				ultravisor.__send__(:process_events)
			end

			it "starts up all children in order" do
				expect(child1).to receive(:spawn).ordered
				expect(child2).to receive(:spawn).ordered
				expect(child3).to receive(:spawn).ordered

				ultravisor.__send__(:process_events)
			end
		end

		context "with a rest_for_one strategy" do
			let(:args) do
				{
					strategy: :rest_for_one,
					children: [
						{
							id: :one,
							klass: Object,
							method: :to_s,
						},
						{
							id: :two,
							klass: Object,
							method: :to_s,
						},
						{
							id: :three,
							klass: Object,
							method: :to_s,
						},
						{
							id: :four,
							klass: Object,
							method: :to_s,
						},
					]
				}
			end

			let(:child1) { Ultravisor::Child.new(id: :one, klass: Object, method: :to_s) }
			let(:child2) { Ultravisor::Child.new(id: :two, klass: Object, method: :to_s) }
			let(:child3) { Ultravisor::Child.new(id: :three, klass: Object, method: :to_s) }
			let(:child4) { Ultravisor::Child.new(id: :four, klass: Object, method: :to_s) }

			before(:each) do
				ultravisor.instance_variable_set(:@children, [[:one, child1], [:two, child2], [:three, child3], [:four, child4]])
				allow(ultravisor.instance_variable_get(:@queue)).to receive(:pop).and_return(child2, :shutdown)
				allow(ultravisor).to receive(:sleep)
				ultravisor.instance_variable_set(:@running_thread, mock_thread)
			end

			it "shuts down only the children after the failed one, in reverse order" do
				expect(child4).to receive(:shutdown).ordered
				expect(child3).to receive(:shutdown).ordered

				ultravisor.__send__(:process_events)
			end

			it "starts up all the relevant children in order" do
				expect(child2).to receive(:spawn).ordered
				expect(child3).to receive(:spawn).ordered
				expect(child4).to receive(:spawn).ordered

				ultravisor.__send__(:process_events)
			end
		end
	end
end
