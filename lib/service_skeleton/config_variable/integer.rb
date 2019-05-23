# frozen_string_literal: true

require "service_skeleton/config_variable"

class ServiceSkeleton::ConfigVariable::Integer < ServiceSkeleton::ConfigVariable
  private

  def pluck_value(env)
    maybe_default(env) do
      value = env[@name.to_s]

      if value =~ /\A-?\d+\z/
        value.to_i.tap do |i|
          unless @opts[:range].include?(i)
            raise ServiceSkeleton::Error::InvalidEnvironmentError,
                  "Value #{i} for environment variable #{@name} is out of the valid range (must be between #{@opts[:range].first} and #{@opts[:range].last} inclusive)"
          end
        end
      else
        raise ServiceSkeleton::Error::InvalidEnvironmentError,
              "Value #{value.inspect} for environment variable #{@name} is not a valid integer value"
      end
    end
  end
end
