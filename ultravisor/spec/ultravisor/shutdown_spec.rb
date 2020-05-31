require_relative "../spec_helper"

require "ultravisor"

describe Ultravisor do
	let(:args) { {} }
	let(:ultravisor) { Ultravisor.new(**args) }
	let(:mock_thread) { instance_double(Thread) }

	describe "#shutdown" do
		it "takes the @op_m lock" do
			expect(ultravisor.instance_variable_get(:@op_m)).to receive(:synchronize).and_call_original

			ultravisor.shutdown
		end

		context "when the ultravisor isn't running" do
			it "returns itself" do
				expect(ultravisor.shutdown).to eq(ultravisor)
			end
		end

		context "when the ultravisor is running" do
			before(:each) do
				ultravisor.instance_variable_set(:@running_thread, mock_thread)
				allow(ultravisor.instance_variable_get(:@op_cv))
					.to receive(:wait) do
						ultravisor.instance_variable_set(:@running_thread, nil)
					end
			end

			it "signals the ultravisor to shutdown" do
				expect(ultravisor.instance_variable_get(:@queue)).to receive(:<<).with(:shutdown)

				ultravisor.shutdown
			end

			it "waits until the CV is signalled" do
				expect(ultravisor.instance_variable_get(:@op_cv)).to receive(:wait) do |m|
						expect(m).to eq(ultravisor.instance_variable_get(:@op_m))
						ultravisor.instance_variable_set(:@running_thread, nil)
						nil
					end

				ultravisor.shutdown
			end

			context "when asked to not wait" do
				it "doesn't wait on the CV" do
					expect(ultravisor.instance_variable_get(:@op_cv)).to_not receive(:wait)

					ultravisor.shutdown(wait: false)
				end
			end

			it "returns itself" do
				expect(ultravisor.shutdown).to eq(ultravisor)
			end

			context "when forced" do
				before(:each) do
					allow(mock_thread).to receive(:kill)
				end

				it "kills the thread" do
					expect(mock_thread).to receive(:kill)

					ultravisor.shutdown(force: true)
				end

				it "tells everyone waiting for the shutdown that the deed is done" do
					expect(ultravisor.instance_variable_get(:@op_cv)).to receive(:broadcast)

					ultravisor.shutdown(force: true)
				end

				it "unsets the running thread" do
					ultravisor.shutdown(force: true)

					expect(ultravisor.instance_variable_get(:@running_thread)).to be(nil)
				end

				it "doesn't wait on the CV" do
					expect(ultravisor.instance_variable_get(:@op_cv)).to_not receive(:wait)

					ultravisor.shutdown(force: true)
				end

				context "with children" do
					let(:child) { Ultravisor::Child.new(id: :one, klass: Object, method: :to_s) }

					before(:each) do
						ultravisor.instance_variable_set(:@children, [[:child, child]])
					end

					it "forcibly shuts down the children" do
						expect(child).to receive(:shutdown).with(force: true)

						ultravisor.shutdown(force: true)
					end
				end
			end
		end
	end
end
