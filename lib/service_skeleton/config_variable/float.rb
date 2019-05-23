# frozen_string_literal: true

require "service_skeleton/config_variable"

class ServiceSkeleton::ConfigVariable::Float < ServiceSkeleton::ConfigVariable
  private

  def pluck_value(env)
    maybe_default(env) do
      value = env[@name.to_s]

      if value =~ /\A-?\d+.?\d*\z/
        value.to_f.tap do |f|
          unless @opts[:range].include?(f)
            raise ServiceSkeleton::Error::InvalidEnvironmentError,
                  "Value #{f} for environment variable #{@name} is out of the valid range (must be between #{@opts[:range].first} and #{@opts[:range].last} inclusive)"
          end
        end
      else
        raise ServiceSkeleton::Error::InvalidEnvironmentError,
              "Value #{value.inspect} for environment variable #{@name} is not a valid numeric value"
      end
    end
  end
end
