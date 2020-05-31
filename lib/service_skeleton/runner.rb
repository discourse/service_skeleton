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

      begin
        @ultravisor.add_child(
          id: klass.service_name.to_sym,
          klass: klass,
          method: :run,
          args: [config: @config, metrics: @metrics_registry]
        )
      rescue Ultravisor::InvalidKAMError
        raise ServiceSkeleton::Error::InvalidServiceClassError,
              "Class #{klass.to_s} does not implement the `run' instance method"
      end
    end

    def run
      logger.info(logloc) { "Starting service #{@config.service_name}" }
      logger.info(logloc) { (["Environment:"] + @config.env.map { |k, v| "#{k}=#{v.inspect}" }).join("\n  ") }

      @ultravisor.run
    end

    private

    attr_reader :logger
  end
end
