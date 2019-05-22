# frozen_string_literal: true

class ServiceSkeleton
  class Error < StandardError
    class InvalidEnvironmentError < Error; end
    class CannotSanitizeEnvironmentError < Error; end
    class InheritanceContractError < Error; end
    class InvalidMetricNameError < Error; end
  end
end
