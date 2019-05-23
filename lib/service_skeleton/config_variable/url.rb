# frozen_string_literal: true

require "service_skeleton/config_variable"

class ServiceSkeleton::ConfigVariable::URL < ServiceSkeleton::ConfigVariable
  def redact!(env)
    if env.has_key?(@name.to_s)
      super
      uri = URI(env[@name.to_s])
      if uri.password
        uri.password = "*REDACTED*"
        env[@name.to_s] = uri.to_s
      end
    end
  end

  private

  def pluck_value(env)
    maybe_default(env) do
      begin
        v = env[@name.to_s]
        URI(v)
      rescue URI::InvalidURIError
        raise ServiceSkeleton::Error::InvalidEnvironmentError,
              "Value for #{@name} (#{v}) does not appear to be a valid URL"
      end

      v
    end
  end
end
