class Ultravisor
	# Base class of all Ultravisor-specific errors
	class Error < StandardError; end

	# Tried to register a child with an ID of a child that already exists
	class DuplicateChildError < Error; end

	# Tried to call `#run` on an ultravisor that is already running
	class AlreadyRunningError < Error; end

	# A `child.call.<method>` was interrupted by the child instance runner terminating
	class ChildRestartedError < Error; end

	# Something was wrong with the Klass/Args/Method (KAM) passed
	class InvalidKAMError < Error; end

	# A child's restart policy was exceeded, and the Ultravisor should
	# terminate
	class BlownRestartPolicyError < Error; end

	# An internal programming error (aka "a bug") caused a violation of thread safety
	# requirements
	class ThreadSafetyError < Error; end
end
