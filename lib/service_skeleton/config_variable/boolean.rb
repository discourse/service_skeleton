# frozen_string_literal: true

require "service_skeleton/config_variable"

class ServiceSkeleton::ConfigVariable::Boolean < ServiceSkeleton::ConfigVariable
  private

  def pluck_value(env)
    maybe_default(env) do
      case env[@name.to_s]
      when /\A(no|n|off|0|false)\z/i
        false
      when /\A(yes|y|on|1|true)\z/i
        true
      else
        raise ServiceSkeleton::Error::InvalidEnvironmentError,
              "Value #{env[@name.to_s].inspect} for environment variable #{@name} is not a valid boolean value"
      end
    end
  end
end
