# frozen_string_literal: true

require_relative "config"
require_relative "logging_helpers"
require_relative "signal_manager"

require "frankenstein/ruby_gc_metrics"
require "frankenstein/ruby_vm_metrics"
require "frankenstein/process_metrics"
require "frankenstein/server"
require "prometheus/client/registry"
require "sigdump"
require "ultravisor"

module ServiceSkeleton
  class Runner
    include ServiceSkeleton::LoggingHelpers

    def initialize(klass, env)
      @config = (klass.config_class || ServiceSkeleton::Config).new(env, klass.service_name, klass.registered_variables)
      @logger = @config.logger

      @metrics_registry = Prometheus::Client::Registry.new

      @ultravisor = ServiceSkeleton.generate(
        config: @config,
        metrics_registry: @metrics_registry,
        service_metrics: klass.registered_metrics,
        service_signal_handlers: { klass.service_name.to_sym => klass.registered_signal_handlers }
      )

      klass.register_ultravisor_children(@ultravisor, config: @config, metrics_registry: @metrics_registry)
    end

    def run
      @config.pre_logger.info(logloc) { "Starting service #{@config.service_name}" }
      @config.pre_logger.info(logloc) { (["Environment:"] + @config.env.map { |k, v| "#{k}=#{v.inspect}" }).join("\n  ") }

      @ultravisor.run
    end

    private

    attr_reader :logger
  end
end
