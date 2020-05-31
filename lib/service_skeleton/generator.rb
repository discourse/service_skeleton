# frozen_string_literal: true

require_relative "config"
require_relative "signal_manager"
require_relative "ultravisor_loggerstash"

require "frankenstein/ruby_gc_metrics"
require "frankenstein/ruby_vm_metrics"
require "frankenstein/process_metrics"
require "frankenstein/server"
require "prometheus/client/registry"
require "sigdump"
require "ultravisor"

module ServiceSkeleton
  module Generator
    def generate(config:, metrics_registry:, service_metrics:, service_signal_handlers:)
      Ultravisor.new(logger: config.logger).tap do |ultravisor|
        initialize_metrics(ultravisor, config, metrics_registry, service_metrics)
        initialize_loggerstash(ultravisor, config, metrics_registry)
        initialize_signals(ultravisor, config, service_signal_handlers, metrics_registry)
      end
    end

    private

    def initialize_metrics(ultravisor, config, registry, metrics)
      Frankenstein::RubyGCMetrics.register(registry)
      Frankenstein::RubyVMMetrics.register(registry)
      Frankenstein::ProcessMetrics.register(registry)

      metrics.each do |m|
        registry.register(m)

        method_name = m.method_name(config.service_name)

        if registry.singleton_class.method_defined?(method_name)
          raise ServiceSkeleton::Error::InvalidMetricNameError,
                "Metric method #{method_name} is already defined"
        end

        registry.define_singleton_method(method_name) do
          m
        end
      end

      if config.metrics_port
        config.logger.info(config.service_name) { "Starting metrics server on port #{config.metrics_port}" }
        ultravisor.add_child(
          id: :metrics_server,
          klass: Frankenstein::Server,
          method: :run,
          args: [
            port: config.metrics_port,
            logger: config.logger,
            metrics_prefix: :"#{config.service_name}_metrics_server",
            registry: registry,
          ]
        )
      end
    end

    def initialize_loggerstash(ultravisor, config, registry)
      if config.logstash_server && !config.logstash_server.empty?
        config.logger.info(config.service_name) { "Configuring loggerstash to send to #{config.logstash_server}" }

        ultravisor.add_child(
          id: :logstash_writer,
          klass: LogstashWriter,
          method: :run,
          args: [
            server_name: config.logstash_server,
            metrics_registry: registry,
            logger: config.logger,
          ],
          access: :unsafe
        )

        config.logger.singleton_class.prepend(Loggerstash::Mixin)

        config.logger.instance_variable_set(:@ultravisor, ultravisor)
        config.logger.singleton_class.prepend(ServiceSkeleton::UltravisorLoggerstash)
      end
    end

    def initialize_signals(ultravisor, config, service_signals, metrics_registry)
      counter = metrics_registry.counter(:"#{config.service_name}_signals_handled_total", "How many of each signal have been handled")

      ultravisor.add_child(
        id: :signal_manager,
        klass: ServiceSkeleton::SignalManager,
        method: :run,
        args: [
          logger: config.logger,
          counter: counter,
          signals: global_signals(ultravisor) + wrap_service_signals(service_signals, ultravisor),
        ],
        shutdown: {
          method: :shutdown,
          timeout: 1,
        }
      )
    end

    def global_signals(ultravisor)
      # For mysterious reasons of mystery, simplecov doesn't recognise these
      # procs as being called, even though there are definitely tests for
      # them.  So...
      #:nocov:
      [
        [
          "USR1",
          ->() {
            logger.level -= 1 unless logger.level == Logger::DEBUG
            logger.info($0) { "Received SIGUSR1; log level is now #{Logger::SEV_LABEL[logger.level]}." }
          }
        ],
        [
          "USR2",
          ->() {
            logger.level += 1 unless logger.level == Logger::ERROR
            logger.info($0) { "Received SIGUSR2; log level is now #{Logger::SEV_LABEL[logger.level]}." }
          }
        ],
        [
          "HUP",
          ->() {
            logger.reopen
            logger.info($0) { "Received SIGHUP; log file handle reopened" }
          }
        ],
        [
          "QUIT",
          ->() { Sigdump.dump("+") }
        ],
        [
          "INT",
          ->() {
            ultravisor.shutdown(wait: false, force: !!@shutting_down)
            @shutting_down = true
          }
        ],
        [
          "TERM",
          ->() {
            ultravisor.shutdown(wait: false, force: !!@shutting_down)
            @shutting_down = true
          }
        ]
      ]
      #:nocov:
    end

    def wrap_service_signals(signals, ultravisor)
      [].tap do |signal_list|
        signals.each do |service_name, sigs|
          sigs.each do |sig, proc|
            wrapped_proc = ->() { ultravisor[service_name.to_sym].unsafe_instance.instance_eval(&proc) }
            signal_list << [sig, wrapped_proc]
          end
        end
      end
    end
  end
end
