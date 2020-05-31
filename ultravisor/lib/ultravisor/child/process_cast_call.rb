module Ultravisor::Child::ProcessCastCall
	private

	def process_castcall
		begin
			loop do
				item = @ultravisor_child_castcall_queue.pop(true)

				# Queue has been closed, which is a polite way of saying "we're done here"
				return if item.nil?

				item.go!(self)

				castcall_fd.getc
			end
		rescue ThreadError => ex
			if ex.message != "queue empty"
				#:nocov:
				raise
				#:nocov:
			end
		end
	end

	def castcall_fd
		@ultravisor_child_castcall_fd
	end

	def process_castcall_loop
		#:nocov:
		loop do
			IO.select([castcall_fd], nil, nil)

			process_castcall
		end
		#:nocov:
	end
end
