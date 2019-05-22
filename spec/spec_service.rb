# frozen_string_literal: true

require "service_skeleton"

class SpecService < ServiceSkeleton
  private

  def run
    raise Object.const_get(@env["RAISE_EXCEPTION"]) if @env["RAISE_EXCEPTION"]
  end
end

class CustomConfig < ServiceSkeleton::Config
end

class ConfigService < ServiceSkeleton
  config_class CustomConfig
end
