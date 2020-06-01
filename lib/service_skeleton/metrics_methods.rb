# frozen_string_literal: true

require "prometheus/client"

require_relative "metric_method_name"

Prometheus::Client::Metric.include(ServiceSkeleton::MetricMethodName)

module ServiceSkeleton
  module MetricsMethods
    def registered_metrics
      @registered_metrics || []
    end

    def metric(metric)
      @registered_metrics ||= []

      @registered_metrics << metric
    end

    def counter(name, docstring:, labels: [], preset_labels: {})
      metric(Prometheus::Client::Counter.new(name, docstring: docstring, labels: labels, preset_labels: preset_labels))
    end

    def gauge(name, docstring:, labels: [], preset_labels: {})
      metric(Prometheus::Client::Gauge.new(name, docstring: docstring, labels: labels, preset_labels: preset_labels))
    end

    def summary(name, docstring:, labels: [], preset_labels: {})
      metric(Prometheus::Client::Summary.new(name, docstring: docstring, labels: labels, preset_labels: preset_labels))
    end

    def histogram(name, docstring:, labels: [], preset_labels: {}, buckets: Prometheus::Client::Histogram::DEFAULT_BUCKETS)
      metric(Prometheus::Client::Histogram.new(name, docstring: docstring, labels: labels, preset_labels: preset_labels, buckets: buckets))
    end
  end
end
