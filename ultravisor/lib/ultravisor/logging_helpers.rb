# frozen_string_literal: true

class Ultravisor
	module LoggingHelpers
		private

		attr_reader :logger

		def log_exception(ex, progname = nil)
			#:nocov:
			progname ||= "#{self.class.to_s}##{caller_locations(2, 1).first.label}"

			logger.error(progname) do
				explanation = if block_given?
					yield
				else
					false
				end

				(["#{explanation}#{explanation ? ": " : ""}#{ex.message} (#{ex.class})"] + ex.backtrace).join("\n  ")
			end
			#:nocov:
		end

		def logloc
			#:nocov:
			loc = caller_locations.first
			"#{self.class}##{loc.label}"
			#:nocov:
		end
	end
end
