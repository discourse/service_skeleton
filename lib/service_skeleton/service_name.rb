# frozen_string_literal: true

module ServiceSkeleton
  module ServiceName
    def service_name
      service_name_from_class(self)
    end

    private

    def service_name_from_class(klass)
      klass.to_s
        .gsub("::", "_")
        .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
        .gsub(/([a-z\d])([A-Z])/, '\1_\2')
        .downcase
        .gsub(/[^a-zA-Z0-9_]/, "_")
    end
  end
end
