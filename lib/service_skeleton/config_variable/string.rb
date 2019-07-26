# frozen_string_literal: true

require "service_skeleton/config_variable"

class ServiceSkeleton::ConfigVariable::String < ServiceSkeleton::ConfigVariable
  private

  def pluck_value(env)
    maybe_default(env) do
      env[@name.to_s].tap do |s|
        if @opts[:match] && s !~ @opts[:match]
          raise ServiceSkeleton::Error::InvalidEnvironmentError,
                "Value for #{@name} must match #{@opts[:match]}"
        end
      end
    end
  end
end
