class Ultravisor::Child::Call
	attr_reader :method_name

	def initialize(method_name, args, blk, rv_q, rv_fail)
		@method_name, @args, @blk, @rv_q, @rv_fail = method_name, args, blk, rv_q, rv_fail
	end

	def go!(receiver)
		@rv_q << receiver.__send__(@method_name, *@args, &@blk)
		@rv_q.close
	end

	def child_restarted!
		@rv_q << @rv_fail
	end
end
