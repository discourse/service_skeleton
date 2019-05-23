# frozen_string_literal: true

require "service_skeleton/config_variable"

class ServiceSkeleton::ConfigVariable::Enum < ServiceSkeleton::ConfigVariable
  private

  def pluck_value(env)
    maybe_default(env) do
      v = env[@name.to_s]

      if @opts[:values].is_a?(Array)
        unless @opts[:values].include?(v)
          raise ServiceSkeleton::Error::InvalidEnvironmentError,
                "Invalid value for #{@name}; must be one of #{@opts[:values].join(", ")}"
        end
        v
      elsif @opts[:values].is_a?(Hash)
        unless @opts[:values].keys.include?(v)
          raise ServiceSkeleton::Error::InvalidEnvironmentError,
                "Invalid value for #{@name}; must be one of #{@opts[:values].keys.join(", ")}"
        end
        @opts[:values][v]
      end
    end
  end
end
