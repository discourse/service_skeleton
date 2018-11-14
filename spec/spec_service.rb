require "service_skeleton"

class SpecService < ServiceSkeleton
  private

  def run
    raise Object.const_get(@env["RAISE_EXCEPTION"]) if @env["RAISE_EXCEPTION"]
  end
end
