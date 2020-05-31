module ExampleMethods
	def tmptrace
		require "tracer"
		Tracer.add_filter { |event, file, line, id, binding, klass, *rest| klass.to_s =~ /Ultravisor/ }
		Tracer.on { yield }
	end
end
