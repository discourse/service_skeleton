class ServiceSkeleton
  module LoggingHelpers
    private

    def log_exception(ex, progname = nil)
      progname ||= "#{self.class.to_s}##{caller_locations(2, 1).first.label}"

      logger.error(progname) do
        #:nocov:
        explanation = if block_given?
          yield
        else
          nil
        end
        #:nocov:

        (["#{explanation}#{explanation ? ": " : ""}#{ex.message} (#{ex.class})"] + ex.backtrace).join("\n  ")
      end
    end
  end
end
