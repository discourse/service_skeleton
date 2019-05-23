# frozen_string_literal: true

require "service_skeleton/config_variable"

class ServiceSkeleton::ConfigVariable::KVList < ServiceSkeleton::ConfigVariable
  def redact!(env)
    env.keys.each { |k| env[k] = "*SENSITIVE*" if k =~ @opts[:key_pattern] }
  end

  private

  def pluck_value(env)
    matches = env.select { |k, _| k.to_s =~ @opts[:key_pattern] }

    if matches.empty?
      if @opts.has_key?(:default)
        @opts[:default]
      else
        raise ServiceSkeleton::Error::InvalidEnvironmentError,
              "no keys for key-value list #{@name} specified"
      end
    else
      matches.transform_keys { |k| @opts[:key_pattern].match(k.to_s)[1].to_sym }
    end
  end
end
