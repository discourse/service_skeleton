# frozen_string_literal: true

module ServiceSkeleton
  module UltravisorLoggerstash
    def logstash_writer
      #:nocov:
      @ultravisor[:logstash_writer].unsafe_instance(wait: false)
      #:nocov:
    end

    # logstash_writer will be nil if the logstash_writer worker is not running
    # Ultravisor's restart policy ensures this will never happen at runtime. But
    # it does happen during startup and shutdown. In this case, we want to skip
    # writing to logstash, not block forever. STDOUT logging will continue.
    def loggerstash_log_message(*args)
      super if !logstash_writer.nil?
    end
  end
end
