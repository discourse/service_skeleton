# frozen_string_literal: true

module ServiceSkeleton
  class Error < StandardError
    class CannotSanitizeEnvironmentError < Error; end
    class InvalidEnvironmentError < Error; end
    class InvalidMetricNameError < Error; end
    class InvalidServiceClassError < Error; end
  end
end
