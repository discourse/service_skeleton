class Ultravisor::Child::CastReceiver < BasicObject
	def initialize(&blk)
		@blk = blk
	end

	def method_missing(name, *args, &blk)
		castback = ::Ultravisor::Child::Cast.new(name, args, blk)
		@blk.call(castback)
	end
end
