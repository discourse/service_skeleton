# frozen_string_literal: true

require "to_regexp"

require_relative "./filtering_logger"

require "loggerstash"

module ServiceSkeleton
  class Config
    attr_reader :logger, :pre_logger, :env, :service_name

    def initialize(env, service_name, variables)
      @service_name = service_name

      # Parsing variables will redact the environment, so we want to take a
      # private unredacted copy before that happens for #[] lookup in the
      # future.
      @env = env.to_hash.dup.freeze

      parse_variables(internal_variables + variables, env)

      # Sadly, we can't setup the logger until we know *how* to setup the
      # logger, which requires parsing config variables
      setup_logger
    end

    def [](k)
      @env[k].dup
    end

    private

    def parse_variables(variables, env)
      variables.map do |var|
        var[:class].new(var[:name], env, **var[:opts])
      end.each do |var|
        val = var.value
        method_name = var.method_name(@service_name).to_sym

        define_singleton_method(method_name) do
          val
        end

        define_singleton_method(:"#{method_name}=") do |new_value|
          val = new_value
        end
      end.each do |var|
        if var.redact?(env)
          if env.object_id != ENV.object_id
            raise ServiceSkeleton::Error::CannotSanitizeEnvironmentError,
                  "Attempted to sanitize sensitive variable #{var.name}, but we're not operating on the process' environment"
          else
            var.redact!(env)
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

      # Can be used prior to a call to ultravisor#run. This prevents a race condition
      # when a logstash server is configured but the logstash writer is not yet
      # initialised.
      @pre_logger = Logger.new(log_file || $stderr, shift_age, shift_size)

      if Thread.main
        Thread.main[:thread_map_number] = 0
      else
        #:nocov:
        Thread.current[:thread_map_number] = 0
        #:nocov:
      end

      thread_map_mutex = Mutex.new

      [@logger, @pre_logger].each do |logger|
        logger.formatter = ->(s, t, p, m) do
          th_n = if Thread.current.name
            #:nocov:
            Thread.current.name
            #:nocov:
          else
            thread_map_mutex.synchronize do
              Thread.current[:thread_map_number] ||= begin
                Thread.list.select { |th| th[:thread_map_number] }.length
              end
            end
          end

          ts = log_enable_timestamps ? "#{t.utc.strftime("%FT%T.%NZ")} " : ""
          "#{ts}#{$$}##{th_n} #{s[0]} [#{p}] #{m}\n"
        end
      end

      @logger.filters = []
      @env.fetch("#{@service_name.upcase}_LOG_LEVEL", "INFO").split(/\s*,\s*/).each do |spec|
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

    def internal_variables
      [
        { name: "#{@service_name.upcase}_LOG_LEVEL",             class: ConfigVariable::String,  opts: { default: "INFO" } },
        { name: "#{@service_name.upcase}_LOG_ENABLE_TIMESTAMPS", class: ConfigVariable::Boolean, opts: { default: false } },
        { name: "#{@service_name.upcase}_LOG_FILE",              class: ConfigVariable::String,  opts: { default: nil } },
        { name: "#{@service_name.upcase}_LOG_MAX_FILE_SIZE",     class: ConfigVariable::Integer, opts: { default: 1048576, range: 0..Float::INFINITY } },
        { name: "#{@service_name.upcase}_LOG_MAX_FILES",         class: ConfigVariable::Integer, opts: { default: 3,       range: 1..Float::INFINITY } },
        { name: "#{@service_name.upcase}_LOGSTASH_SERVER",       class: ConfigVariable::String,  opts: { default: "" } },
        { name: "#{@service_name.upcase}_METRICS_PORT",          class: ConfigVariable::Integer, opts: { default: nil,     range: 1..65535 } },
      ]
    end
  end
end
