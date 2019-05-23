# frozen_string_literal: true

require "to_regexp"

require_relative "./filtering_logger"

require "loggerstash"

class ServiceSkeleton
  class Config
    attr_reader :logger, :env

    def initialize(env, svc)
      @svc = svc

      # Parsing registered variables will redact the environment, so we want
      # to take a private unredacted copy before that happens
      @env = env.to_hash.dup.freeze

      parse_registered_variables(env)

      # Sadly, we can't setup the logger until we know *how* to setup the
      # logger, which requires parsing config variables
      setup_logger
    end

    def [](k)
      @env[k]
    end

    private

    def parse_registered_variables(env)
      (@svc.registered_variables || []).map do |var|
        var[:class].new(var[:name], env, **var[:opts])
      end.each do |var|
        val = var.value
        method_name = var.method_name(@svc.service_name).to_sym

        define_singleton_method(method_name) do
          val
        end

        define_singleton_method(:"#{method_name}=") do |new_value|
          val = new_value
        end
      end.each do |var|
        if var.redact!(env) && env.object_id != ENV.object_id
          raise ServiceSkeleton::Error::CannotSanitizeEnvironmentError,
                "Attempted to sanitize sensitive variable #{var.name}, but we're not operating on the process' environment"
        end
      end
    end

    def setup_logger
      shift_age, shift_size = if log_max_file_size == 0
        [0, 0]
      else
        [log_max_files, log_max_file_size]
      end

      @logger = Logger.new(log_file || $stderr, shift_age, shift_size)

      if self.logstash_server && !self.logstash_server.empty?
        loggerstash = Loggerstash.new(logstash_server: logstash_server, logger: @logger)
        loggerstash.metrics_registry = @svc.metrics
        loggerstash.attach(@logger)
      end

      thread_id_map = {}
      if Thread.main
        thread_id_map[Thread.main.object_id] = 0
      else
        #:nocov:
        thread_id_map[Thread.current.object_id] = 0
        #:nocov:
      end

      @logger.formatter = ->(s, t, p, m) do
        th_n = thread_id_map[Thread.current.object_id] || (thread_id_map[Thread.current.object_id] = thread_id_map.length)

        ts = log_enable_timestamps ? "#{t.utc.strftime("%FT%T.%NZ")} " : ""
        "#{ts}#{$$}##{th_n} #{s[0]} [#{p}] #{m}\n"
      end

      @logger.filters = []
      @env.fetch("#{@svc.service_name.upcase}_LOG_LEVEL", "INFO").split(/\s*,\s*/).each do |spec|
        if spec.index("=")
          # "Your developers were so preoccupied with whether or not they
          # could, they didn't stop to think if they should."
          re, sev = spec.split(/\s*=\s*(?=[^=]*\z)/)
          match = re.to_regexp || re
          begin
            sev = Logger.const_get(sev.upcase)
          rescue NameError
            raise ServiceSkeleton::Error::InvalidEnvironmentError,
                  "Unknown logger severity #{sev.inspect} specified in #{spec.inspect}"
          end
          @logger.filters << [match, sev]
        else
          begin
            @logger.level = Logger.const_get(spec.upcase)
          rescue NameError
            raise ServiceSkeleton::Error::InvalidEnvironmentError,
                  "Unknown logger severity #{spec.inspect} specified"
          end
        end
      end
    end
  end
end
