class Ultravisor::Child::Cast
	attr_reader :method_name

	def initialize(method_name, args, blk)
		@method_name, @args, @blk = method_name, args, blk
	end

	def go!(receiver)
		receiver.__send__(@method_name, *@args, &@blk)
	end

	def child_restarted!
		# Meh
	end
end
