# frozen_string_literal: true

require "service_skeleton"

class SpecService
  include ServiceSkeleton

  def run
    raise Object.const_get(config.raise_exception) if config.raise_exception
    return if config.return
    sleep
  end
end

class CustomConfig < ServiceSkeleton::Config
end

class ConfigService
  include ServiceSkeleton

  config_class CustomConfig
end
