require "to_regexp"

require_relative "./filtering_logger"

require "loggerstash"

class ServiceSkeleton
  class Config
    attr_reader :logger, :env

    def initialize(env, svc)
      @env = env.to_hash.dup.freeze
      @svc = svc

      parse_registered_variables(env)
      setup_logger
    end

    def [](k)
      @env[k]
    end

    private

    def parse_registered_variables(env)
      @svc.registered_variables.each do |var|
        val = var.value(env[var.name.to_s])
        define_singleton_method(var.method_name(@svc.service_name)) do
          val
        end

        if var.sensitive?
          if env.object_id != ENV.object_id
            raise ServiceSkeleton::Error::CannotSanitizeEnvironmentError,
                  "Attempted to sanitize sensitive variable #{var.name}, but was not passed the ENV object"
          end
          env.delete(var.name.to_s)
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

      if log_enable_timestamps
        @logger.formatter = ->(s, t, p, m) { "#{t.utc.strftime("%FT%T.%NZ")} #{s[0]} [#{p}] #{m}\n" }
      else
        @logger.formatter = ->(s, t, p, m) { "#{s[0]} [#{p}] #{m}\n" }
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
