# frozen_string_literal: true

require_relative "./logging_helpers"

class Ultravisor
	class Child
		include LoggingHelpers

		attr_reader :id

		def initialize(id:,
		               klass:,
		               args: [],
		               method:,
		               restart: :always,
		               restart_policy: {
		                  period: 5,
		                  max: 3,
		                  delay: 1,
		               },
		               shutdown: {
		                  method: nil,
		                  timeout: 1,
		               },
		               logger: Logger.new("/dev/null"),
		               enable_castcall: false,
		               access: nil
		              )
			@logger = logger
			@id = id

			@klass, @args, @method = klass, args, method
			validate_kam

			@restart = restart
			validate_restart

			@restart_policy = restart_policy
			validate_restart_policy

			@shutdown_spec = shutdown
			validate_shutdown_spec

			@access = access
			validate_access

			@enable_castcall = enable_castcall

			@runtime_history = []

			@spawn_m    = Mutex.new
			@spawn_cv   = ConditionVariable.new

			@shutdown_m = Mutex.new
		end

		def spawn(term_queue)
			@spawn_m.synchronize do
				@value      = nil
				@exception  = nil
				@start_time = Time.now
				@instance   = new_instance

				@spawn_id = sid = rand

				Thread.handle_interrupt(::Exception => :never, ::Numeric => :never) do
					@thread = Thread.new do
						Thread.current.name = @id.to_s
						begin
							Thread.handle_interrupt(::Exception => :immediate, ::Numeric => :immediate) do
								@value = @instance.public_send(@method)
							end
						rescue Exception => ex
							@exception = ex
						ensure
							@spawn_m.synchronize do
								# Even if a thread gets whacked by Thread#kill, ensure blocks
								# still get run.  This is... wonderful!  And terrifying!

								termination_cleanup(term_queue) if @spawn_id == sid
							end
						end
					end
				end

				@spawn_cv.broadcast
			end

			self
		end

		def shutdown(force: false)
			@shutdown_m.synchronize do
				th  = nil
				sid = nil

				@spawn_m.synchronize do
					return if @thread.nil? || @thread == Thread.current

					# Take a reference to the running thread, so we don't need to
					# keep acquiring spawn_m every time we want to do something
					# with it -- which causes collisions when it comes time to
					# wait on the terminating thread, which is itself is trying
					# to acquire the same lock so it can cleanup.
					th  = @thread
					sid = @spawn_id

					# Let everyone know we're in shutdown mode
					@shutting_down = true
				end

				if @shutdown_spec[:method] && !force
					@instance.public_send(@shutdown_spec[:method])
				else
					th.kill
				end

				unless th.join(@shutdown_spec[:timeout])
					logger.info(logloc) { "Child instance for #{self.id} did not cleanly shutdown within #{@shutdown_spec[:timeout]} seconds; force-killing the thread" }
					th.kill
				end

				# Last chance, bubs
				unless th.join(0.1)
					logger.error(logloc) { "Child thread for #{self.id} appears hung; abandoning thread #{th}" }

					# If we get here, then the worker instance has seized up spectacularly,
					# and the cleanup in the `spawn` ensure hasn't triggered, so we need
					# to do the cleanup instead.
					@spawn_m.synchronize do
						termination_cleanup if @spawn_id == sid
					end
				end
			end
		end

		def wait
			@spawn_m.synchronize do
				@spawn_cv.wait(@spawn_m) while @thread
			end
		end

		def termination_exception
			@spawn_m.synchronize do
				@spawn_cv.wait(@spawn_m) while @thread
				@exception
			end
		end

		def termination_value
			@spawn_m.synchronize do
				@spawn_cv.wait(@spawn_m) while @thread
				@value
			end
		end

		def restart_delay
			d = begin
				case @restart_policy[:delay]
				when Numeric
					@restart_policy[:delay]
				when Range
					@restart_policy[:delay].first + (@restart_policy[:delay].last - @restart_policy[:delay].first) * rand
				end
			end

			[0, d].max
		end

		def restart?
			if blown_policy?
				raise BlownRestartPolicyError,
				      "Child #{self.id} has restarted more than #{@restart_policy[:max]} times in #{@restart_policy[:period]} seconds."
			end

			!!(@restart == :always || (@restart == :on_failure && termination_exception))
		end

		def unsafe_instance
			unless @access == :unsafe
				raise Ultravisor::ThreadSafetyError,
				      "#unsafe_instance called on a child not declared with access: :unsafe"
			end

			current_instance
		end

		def cast
			unless castcall_enabled?
				raise NoMethodError,
				      "undefined method `cast' for #{self}"
			end

			CastReceiver.new do |castback|
				@spawn_m.synchronize do
					while @instance.nil?
						#:nocov:
						@spawn_cv.wait(@spawn_m)
						#:nocov:
					end

					unless @instance.respond_to? castback.method_name
						raise NoMethodError,
						      "undefined method `#{castback.method_name}' for #{@instance}"
					end

					begin
						@instance.instance_variable_get(:@ultravisor_child_castcall_queue) << castback
					rescue ClosedQueueError
						# casts aren't guaranteed to ever execute, so dropping it
						# when the instance's queue has closed is perfectly valid
					end

					@castcall_fd_writer.putc "!"
				end
			end
		end

		def call
			unless castcall_enabled?
				raise NoMethodError,
				      "undefined method `call' for #{self}"
			end

			CallReceiver.new do |callback|
				@spawn_m.synchronize do
					while @instance.nil?
						#:nocov:
						@spawn_cv.wait(@spawn_m)
						#:nocov:
					end

					unless @instance.respond_to? callback.method_name
						raise NoMethodError,
						      "undefined method `#{callback.method_name}' for #{@instance}"
					end

					begin
						@instance.instance_variable_get(:@ultravisor_child_castcall_queue) << callback
					rescue ClosedQueueError
						raise ChildRestartedError
					end

					@castcall_fd_writer.putc "!"
				end
			end
		end

		private

		def validate_kam
			if @klass.instance_method(:initialize).arity == 0 && @args != []
				raise InvalidKAMError,
				      "#{@klass.to_s}.new takes no arguments, but args not empty."
			end

			begin
				if @klass.instance_method(@method).arity != 0
					raise InvalidKAMError,
					      "#{@klass.to_s}##{@method} must not take arguments"
				end
			rescue NameError
				raise InvalidKAMError,
				      "#{@klass.to_s} has no instance method #{@method}"
			end
		end

		def validate_restart
			unless %i{never on_failure always}.include?(@restart)
				raise ArgumentError,
				      "Invalid value for restart: #{@restart.inspect}"
			end
		end

		def validate_restart_policy
			unless @restart_policy.is_a?(Hash)
				raise ArgumentError,
				      "restart_policy must be a hash (got #{@restart_policy.inspect})"
			end

			bad_keys = @restart_policy.keys - %i{period max delay}
			unless bad_keys.empty?
				raise ArgumentError,
				      "Invalid key(s) in restart_policy: #{bad_keys.inspect}"
			end

			# Restore any missing defaults
			@restart_policy = { period: 5, max: 3, delay: 1 }.merge(@restart_policy)

			unless @restart_policy[:period].is_a?(Numeric) && @restart_policy[:period].positive?
				raise ArgumentError,
				      "Invalid restart_policy period #{@restart_policy[:period].inspect}: must be positive integer"
			end

			unless @restart_policy[:max].is_a?(Numeric) && !@restart_policy[:max].negative?
				raise ArgumentError,
				      "Invalid restart_policy max #{@restart_policy[:period].inspect}: must be non-negative integer"
			end

			case @restart_policy[:delay]
			when Numeric
				if @restart_policy[:delay].negative?
					raise ArgumentError,
					      "Invalid restart_policy delay #{@restart_policy[:delay].inspect}: must be non-negative integer or range"
				end
			when Range
				if @restart_policy[:delay].first >= @restart_policy[:delay].last
					raise ArgumentError,
					      "Invalid restart_policy delay #{@restart_policy[:delay].inspect}: must be non-negative integer or increasing range"
				end

				if @restart_policy[:delay].first.negative?
					raise ArgumentError,
					      "Invalid restart_policy delay #{@restart_policy[:delay].inspect}: range must not be negative"
				end
			else
				raise ArgumentError,
				      "Invalid restart_policy delay #{@restart_policy[:delay].inspect}: must be non-negative integer or range"
			end
		end

		def validate_shutdown_spec
			unless @shutdown_spec.is_a?(Hash)
				raise ArgumentError,
				      "shutdown must be a hash (got #{@shutdown_spec.inspect})"
			end

			bad_keys = @shutdown_spec.keys - %i{method timeout}
			unless bad_keys.empty?
				raise ArgumentError,
				      "Invalid key(s) in shutdown specification: #{bad_keys.inspect}"
			end

			# Restore any missing defaults
			@shutdown_spec = { method: nil, timeout: 1 }.merge(@shutdown_spec)

			if @shutdown_spec[:method]
				begin
					unless @klass.instance_method(@shutdown_spec[:method]).arity == 0
						raise ArgumentError,
						      "Shutdown method #{@klass.to_s}##{@shutdown_spec[:method]} must not take any arguments"
					end
				rescue NameError
					raise ArgumentError,
					      "Shutdown method #{@klass.to_s}##{@shutdown_spec[:method]} is not defined"
				end
			end

			unless @shutdown_spec[:timeout].is_a?(Numeric) && !@shutdown_spec[:timeout].negative?
				raise ArgumentError,
				      "Invalid shutdown timeout #{@shutdown_spec[:timeout].inspect}: must be non-negative integer"
			end
		end

		def validate_access
			return if @access.nil?

			unless %i{unsafe}.include? @access
				raise ArgumentError,
				      "Invalid instance access specification: #{@access.inspect}"
			end
		end

		def castcall_enabled?
			!!@enable_castcall
		end

		def new_instance
			# If there is anything that pisses me off about Ruby's varargs handling more
			# than the fact that *[] is an empty array, and not a zero-length argument
			# list, I don't know what it is.  Everything else works *so well*, and this...
			# urgh.
			if @klass.instance_method(:initialize).arity == 0
				@klass.new()
			else
				@klass.new(*@args)
			end.tap do |i|
				if castcall_enabled?
					i.singleton_class.prepend(Ultravisor::Child::ProcessCastCall)
					i.instance_variable_set(:@ultravisor_child_castcall_queue, Queue.new)

					r, @castcall_fd_writer = IO.pipe
					i.instance_variable_set(:@ultravisor_child_castcall_fd, r)
				end
			end
		end

		def current_instance
			@spawn_m.synchronize do
				while @instance.nil?
					@spawn_cv.wait(@spawn_m)
				end

				return @instance
			end
		end

		def blown_policy?
			cumulative_runtime = 0
			recent_restart_count = 0

			@runtime_history.each_with_index do |t, i|
				cumulative_runtime += t

				if cumulative_runtime > @restart_policy[:period]
					recent_restart_count = i + 1
					break
				end
			end

			logger.debug(logloc) { "@runtime_history: #{@runtime_history.inspect}, cumulative_runtime: #{cumulative_runtime}, recent_restart_count: #{recent_restart_count}, restart_policy: #{@restart_policy.inspect}" }

			if recent_restart_count > @restart_policy[:max]
				return true
			end

			@runtime_history = @runtime_history[0..recent_restart_count]

			false
		end

		def termination_cleanup(term_queue = nil)
			unless @spawn_m.owned?
				#:nocov:
				raise ThreadSafetyError,
				      "termination_cleanup must be called while holding the @spawn_m lock"
				#:nocov:
			end

			if @start_time
				@runtime_history.unshift(Time.now.to_f - @start_time.to_f)
				@start_time = nil
			end

			term_queue << self if term_queue && !@shutting_down

			if castcall_enabled?
				cc_q = @instance.instance_variable_get(:@ultravisor_child_castcall_queue)
				cc_q.close
				x = 0
				begin
					loop do
						cc_q.pop(true).child_restarted!
					end
				rescue ThreadError => ex
					raise unless ex.message == "queue empty"
				end

				@instance.instance_variable_get(:@ultravisor_child_castcall_fd).close
				@instance.instance_variable_set(:@ultravisor_child_castcall_fd, nil)
				@castcall_fd_writer.close
				@castcall_fd_writer = nil
			end

			@instance = nil

			if @thread
				@thread = nil
				@spawn_cv.broadcast
			end

			@spawn_id = nil
		end
	end
end

require_relative "./child/call"
require_relative "./child/call_receiver"
require_relative "./child/cast"
require_relative "./child/cast_receiver"
require_relative "./child/process_cast_call"
