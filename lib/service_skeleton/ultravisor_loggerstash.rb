# frozen_string_literal: true

module ServiceSkeleton
  module UltravisorLoggerstash
    def logstash_writer
      #:nocov:
      @ultravisor[:logstash_writer].unsafe_instance
      #:nocov:
    end
  end
end
