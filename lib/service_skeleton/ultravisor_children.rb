# frozen_string_literal: true

module ServiceSkeleton
  module UltravisorChildren
    def register_ultravisor_children(ultravisor, config:, metrics_registry:)
      begin
        ultravisor.add_child(
          id: self.service_name.to_sym,
          klass: self,
          method: :run,
          args: [config: config, metrics: metrics_registry]
        )
      rescue Ultravisor::InvalidKAMError
        raise ServiceSkeleton::Error::InvalidServiceClassError,
              "Class #{self.to_s} does not implement the `run' instance method"
      end
    end
  end
end
