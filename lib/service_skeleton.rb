require_relative "service_skeleton/config"
require_relative "service_skeleton/config_variables"
require_relative "service_skeleton/logging_helpers"
require_relative "service_skeleton/metrics_methods"
require_relative "service_skeleton/signal_handler"

require "frankenstein/ruby_gc_metrics"
require "frankenstein/ruby_vm_metrics"
require "frankenstein/process_metrics"
require "frankenstein/server"
require "prometheus/client/registry"
require "sigdump"

class ServiceSkeleton
  extend ServiceSkeleton::ConfigVariables

  include ServiceSkeleton::LoggingHelpers

  class Terminate < Exception; end

  def self.config_class(klass)
    @config_class = klass
  end

  def self.service_name
    self.to_s
      .gsub("::", "_")
      .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
      .gsub(/([a-z\d])([A-Z])/, '\1_\2')
      .downcase
  end

  attr_reader :config, :metrics, :logger

  def initialize(env)
    @env      = env
    @config   = (self.class.instance_variable_get(:@config_class) || ServiceSkeleton::Config).new(env, self)
    @logger   = @config.logger
    @op_mutex = Mutex.new

    setup_metrics
    setup_signals
  end

  def start
    @op_mutex.synchronize { @thread = Thread.current }

    begin
      start_metrics_server
      start_signal_handler
      run
    rescue ServiceSkeleton::Terminate
      # This one is OK
    rescue ServiceSkeleton::Error::InheritanceContractError
      # We want this one to be fatal
      raise
    rescue StandardError => ex
      log_exception(ex)
    end

    @thread = nil
  end

  def stop(force = false)
    if force
      #:nocov:
      @op_mutex.synchronize do
        if @thread
          @thread.raise(ServiceSkeleton::Terminate)
        end
      end
      #:nocov:
    else
      shutdown
    end

    if @metrics_server
      @metrics_server.shutdown
      @metrics_server = nil
    end

    @signal_handler.stop!
  end

  def service_name
    self.class.service_name
  end

  def registered_variables
    self.class.registered_variables
  end

  def hook_signal(spec, &blk)
    @signal_handler.hook_signal(spec, &blk)
  end

  private

  def run
    raise ServiceSkeleton::Error::InheritanceContractError, "ServiceSkeleton#run method not overridden"
  end

  def shutdown
    #:nocov:
    @op_mutex.synchronize do
      if @thread
        @thread.raise(ServiceSkeleton::Terminate)
        @thread.join
        @thread = nil
      end
    end
    #:nocov:
  end

  def setup_metrics
    @metrics = Prometheus::Client::Registry.new

    Frankenstein::RubyGCMetrics.register(@metrics)
    Frankenstein::RubyVMMetrics.register(@metrics)
    Frankenstein::ProcessMetrics.register(@metrics)

    @metrics.singleton_class.prepend(ServiceSkeleton::MetricsMethods)
    @metrics.service = self

  end

  def start_metrics_server
    if config.metrics_port
      logger.info(self.class.to_s) { "Starting metrics server on port #{config.metrics_port}" }

      @metrics_server = Frankenstein::Server.new(
        port: config.metrics_port,
        logger: logger,
        metrics_prefix: :metrics_server,
        registry: @metrics,
      )
      @metrics_server.run
    end
  end

  def setup_signals
    @signal_handler = ServiceSkeleton::SignalHandler.new(logger: logger, service: self, signal_counter: metrics.counter(:"#{self.service_name}_signals_handled_total", "How many of each type of signal have been handled"))

    @signal_handler.hook_signal("USR1") do
      logger.level -= 1 unless logger.level == Logger::DEBUG
      logger.info($0) { "Received SIGUSR1; log level is now #{Logger::SEV_LABEL[logger.level]}." }
    end

    @signal_handler.hook_signal("USR2") do
      logger.level += 1 unless logger.level == Logger::ERROR
      logger.info($0) { "Received SIGUSR2; log level is now #{Logger::SEV_LABEL[logger.level]}." }
    end

    @signal_handler.hook_signal("HUP") do
      logger.reopen
      logger.info($0) { "Received SIGHUP; log file handle reopened" }
    end

    @signal_handler.hook_signal("QUIT") do
      Sigdump.dump("+")
    end

    @signal_handler.hook_signal("INT") do
      self.stop(!!@terminating)
      @terminating = true
    end

    @signal_handler.hook_signal("TERM") do
      self.stop(!!@terminating)
      @terminating = true
    end
  end

  def start_signal_handler
    @signal_handler.start!
  end

  @registered_variables = [
    ServiceSkeleton::ConfigVariable.new(:SERVICE_SKELETON_LOG_LEVEL) { "INFO" },
    ServiceSkeleton::ConfigVariable.new(:SERVICE_SKELETON_LOGSTASH_SERVER) { "" },
    ServiceSkeleton::ConfigVariable.new(:SERVICE_SKELETON_LOG_ENABLE_TIMESTAMPS) { false },
    ServiceSkeleton::ConfigVariable.new(:SERVICE_SKELETON_LOG_FILE) { nil },
    ServiceSkeleton::ConfigVariable.new(:SERVICE_SKELETON_LOG_MAX_FILE_SIZE) { 1048576 },
    ServiceSkeleton::ConfigVariable.new(:SERVICE_SKELETON_LOG_MAX_FILES) { 3 },
    ServiceSkeleton::ConfigVariable.new(:SERVICE_SKELETON_METRICS_PORT) { nil },
  ]

  def self.inherited(subclass)
    subclass.string(:"#{subclass.service_name.upcase}_LOG_LEVEL", default: "INFO")
    subclass.string(:"#{subclass.service_name.upcase}_LOGSTASH_SERVER", default: "")
    subclass.boolean(:"#{subclass.service_name.upcase}_LOG_ENABLE_TIMESTAMPS", default: false)
    subclass.string(:"#{subclass.service_name.upcase}_LOG_FILE", default: nil)
    subclass.integer(:"#{subclass.service_name.upcase}_LOG_MAX_FILE_SIZE", default: 1048576, range: 0..Float::INFINITY)
    subclass.integer(:"#{subclass.service_name.upcase}_LOG_MAX_FILES", default: 3, range: 1..Float::INFINITY)
    subclass.integer(:"#{subclass.service_name.upcase}_METRICS_PORT", default: nil, range: 1..65535)
  end
end
