# frozen_string_literal: true

require "logger"

require_relative "./ultravisor/child"
require_relative "./ultravisor/error"
require_relative "./ultravisor/logging_helpers"

# A super-dooOOOoooper supervisor.
#
class Ultravisor
	include LoggingHelpers

	def initialize(children: [], strategy: :one_for_one, logger: Logger.new("/dev/null"))
		@queue, @logger = Queue.new, logger

		@strategy = strategy
		validate_strategy

		@op_m, @op_cv = Mutex.new, ConditionVariable.new
		@running_thread = nil

		initialize_children(children)
	end

	def run
		logger.debug(logloc) { "called" }

		@op_m.synchronize do
			if @running_thread
				raise AlreadyRunningError,
				      "This ultravisor is already running"
			end

			@queue.clear
			@running_thread = Thread.current
		end

		@children.each { |c| c.last.spawn(@queue) }

		process_events

		@op_m.synchronize do
			@children.reverse.each { |c| c.last.shutdown }

			@running_thread = nil
			@op_cv.broadcast
		end

		self
	end

	def shutdown(wait: true, force: false)
		@op_m.synchronize do
			return self unless @running_thread
			if force
				@children.reverse.each { |c| c.last.shutdown(force: true) }
				@running_thread.kill
				@running_thread = nil
				@op_cv.broadcast
			else
				@queue << :shutdown
				if wait
					@op_cv.wait(@op_m) while @running_thread
				end
			end
		end
		self
	end

	def [](id)
		@children.assoc(id)&.last
	end

	def add_child(*args)
		@op_m.synchronize do
			c = Ultravisor::Child.new(*args)

			if @children.assoc(c.id)
				raise DuplicateChildError,
				      "Child with ID #{c.id.inspect} already exists"
			end

			@children << [c.id, c]

			if @running_thread
				c.spawn(@queue)
			end
		end
	end

	private

	def validate_strategy
		unless %i{one_for_one all_for_one rest_for_one}.include?(@strategy)
			raise ArgumentError,
			      "Invalid strategy #{@strategy.inspect}"
		end
	end

	def initialize_children(children)
		unless children.is_a?(Array)
			raise ArgumentError,
			      "children must be an Array"
		end

		@children = []

		children.each do |cfg|
			c = Ultravisor::Child.new(cfg)
			if @children.assoc(c.id)
				raise DuplicateChildError,
				      "Duplicate child ID: #{c.id.inspect}"
			end

		   @children << [c.id, c]
		end
	end

	def process_events
		loop do
			qe = @queue.pop
			logger.debug(logloc) { "Received queue entry #{qe.inspect}" }

			case qe
			when Ultravisor::Child
				@op_m.synchronize { child_exited(qe) }
			when :shutdown
				break
			else
				logger.error(logloc) { "Unknown queue entry: #{qe.inspect}" }
			end
		end
	end

	def child_exited(child)
		if child.termination_exception
			log_exception(child.termination_exception, "Ultravisor::Child(#{child.id.inspect})") { "Thread terminated by unhandled exception" }
		end

		if @running_thread.nil?
			# Child termination processed after we've shut down... nope
			return
		end

		begin
			return unless child.restart?
		rescue Ultravisor::BlownRestartPolicyError
			# Uh oh...
			logger.error(logloc) { "Child #{child.id} has exceeded its restart policy.  Shutting down the Ultravisor." }
			@queue << :shutdown
			return
		end

		case @strategy
		when :all_for_one
			@children.reverse.each do |id, c|
				# Don't need to shut down the child that has caused all this mess
				next if child.id == id

				c.shutdown
			end
		when :rest_for_one
			@children.reverse.each do |id, c|
				# Don't go past the child that caused the problems
				break if child.id == id

				c.shutdown
			end
		end

		sleep child.restart_delay

		case @strategy
		when :all_for_one
			@children.each do |_, c|
				c.spawn(@queue)
			end
		when :rest_for_one
			s = false
			@children.each do |id, c|
				s = true if child.id == id

				c.spawn(@queue) if s
			end
		when :one_for_one
			child.spawn(@queue)
		end
	end
end
