require "to_regexp"

require_relative "./filtering_logger"

require "loggerstash"

class ServiceSkeleton
  class Config
    attr_reader :logger, :env

    def initialize(env, svc)
      @svc = svc

      parse_registered_variables(env)
      @env = env.to_hash.dup.freeze
      setup_logger
    end

    def [](k)
      @env[k]
    end

    private

    def parse_registered_variables(env)
      @svc.registered_variables.each do |var|
        val = var.value(env)

        define_singleton_method(var.method_name(@svc.service_name)) do
          val
        end

        define_singleton_method(var.method_name(@svc.service_name) + "=") do |v|
          val = v
        end

        if var.sensitive?
          if env.object_id != ENV.object_id
            raise ServiceSkeleton::Error::CannotSanitizeEnvironmentError,
                  "Attempted to sanitize sensitive variable #{var.name}, but was not passed the ENV object"
          end

          var.env_keys(env).each do |k|
            env[k] = "*SENSITIVE*"
          end
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
        "#{ts}##{th_n} #{s[0]} [#{p}] #{m}\n"
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
