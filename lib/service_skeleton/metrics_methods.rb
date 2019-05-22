# frozen_string_literal: true

class ServiceSkeleton
  module MetricsMethods
    def service=(svc)
      @service = svc
    end

    def register(metric)
      method_name = metric.name.to_s.gsub(/\A#{Regexp.quote(@service.service_name)}_/, '').to_sym

      if self.class.method_defined?(method_name)
        raise ServiceSkeleton::Error::InvalidMetricNameError,
              "There is already a method named #{method_name} on ##metrics, so you can't have a metric named #{metric.name}"
      end

      define_singleton_method(method_name) do
        metric
      end

      super
    end
  end
end
