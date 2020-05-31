# frozen_string_literal: true

require "yaml"

require "service_skeleton/config_variable"

class ServiceSkeleton::ConfigVariable::YamlFile < ServiceSkeleton::ConfigVariable
  def redact!(env)
    if env.has_key?(@name.to_s)
      if File.world_readable?(env[@name.to_s])
        raise ServiceSkeleton::Error::InvalidEnvironmentError,
              "Sensitive file #{env[@name.to_s]} is world-readable!"
      end

      super
    end
  end

  private

  def pluck_value(env)
    maybe_default(env) do
      begin
        val = YAML.safe_load(File.read(env[@name.to_s]))
        if @opts[:klass]
          val = @opts[:klass].new(val)
        end

        val
      rescue Errno::ENOENT
        raise ServiceSkeleton::Error::InvalidEnvironmentError,
              "YAML file #{env[@name.to_s]} does not exist"
      rescue Errno::EPERM
        raise ServiceSkeleton::Error::InvalidEnvironmentError,
              "Do not have permission to read YAML file #{env[@name.to_s]}"
      rescue Psych::SyntaxError => ex
        raise ServiceSkeleton::Error::InvalidEnvironmentError,
              "Invalid YAML syntax: #{ex.message}"
      end
    end
  end
end
