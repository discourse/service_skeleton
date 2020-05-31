# frozen_string_literal: true

module ServiceSkeleton
  module MetricMethodName
    def method_name(svc_name)
      @name.to_s.gsub(/\A#{Regexp.quote(svc_name)}_/i, '').downcase
    end
  end
end
