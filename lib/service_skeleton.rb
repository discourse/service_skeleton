# frozen_string_literal: true

require_relative "service_skeleton/config_class"
require_relative "service_skeleton/config_variables"
require_relative "service_skeleton/generator"
require_relative "service_skeleton/hurriable_timer"
require_relative "service_skeleton/hurriable_timer_sequence"
require_relative "service_skeleton/logging_helpers"
require_relative "service_skeleton/metrics_methods"
require_relative "service_skeleton/service_name"
require_relative "service_skeleton/signals_methods"
require_relative "service_skeleton/ultravisor_children"

require "frankenstein/ruby_gc_metrics"
require "frankenstein/ruby_vm_metrics"
require "frankenstein/process_metrics"
require "frankenstein/server"
require "prometheus/client/registry"
require "sigdump"

module ServiceSkeleton
  include ServiceSkeleton::LoggingHelpers
  extend ServiceSkeleton::Generator

  def self.included(mod)
    mod.extend ServiceSkeleton::ServiceName
    mod.extend ServiceSkeleton::ConfigVariables
    mod.extend ServiceSkeleton::ConfigClass
    mod.extend ServiceSkeleton::MetricsMethods
    mod.extend ServiceSkeleton::SignalsMethods
    mod.extend ServiceSkeleton::UltravisorChildren
  end

  attr_reader :config, :metrics, :logger

  def initialize(*_, metrics:, config:)
    @metrics = metrics
    @config  = config
    @logger  = @config.logger
  end
end

require_relative "service_skeleton/runner"
