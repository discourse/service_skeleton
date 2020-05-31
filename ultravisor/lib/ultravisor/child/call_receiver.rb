class Ultravisor::Child::CallReceiver < BasicObject
	def initialize(&blk)
		@blk = blk
	end

	def method_missing(name, *args, &blk)
		rv_q = ::Queue.new
		rv_fail = ::Object.new
		callback = ::Ultravisor::Child::Call.new(name, args, blk, rv_q, rv_fail)
		@blk.call(callback)
		rv_q.pop.tap { |rv| ::Kernel.raise ::Ultravisor::ChildRestartedError.new if rv == rv_fail }
	end
end
