# frozen_string_literal: true

require "service_skeleton/config_variable"

class ServiceSkeleton::ConfigVariable::String < ServiceSkeleton::ConfigVariable
  private

  def pluck_value(env)
    maybe_default(env) do
      env[@name.to_s]
    end
  end
end
