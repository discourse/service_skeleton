# frozen_string_literal: true

module ServiceSkeleton
  class ConfigVariable
    attr_reader :name, :value

    def initialize(name, env, **opts, &blk)
      @name = name
      @opts = opts
      @blk  = blk

      @value = pluck_value(env)
    end

    def method_name(svc_name)
      @name.to_s.gsub(/\A#{Regexp.quote(svc_name)}_/i, '').downcase
    end

    def redact?(env)
      @opts[:sensitive]
    end

    def redact!(env)
      if @opts[:sensitive]
        env[@name.to_s] = "*SENSITIVE*" if env.has_key?(@name.to_s)
      end
    end

    private

    def maybe_default(env)
      if env.has_key?(@name.to_s)
        yield
      else
        if @opts.has_key?(:default)
          @opts[:default]
        else
          raise ServiceSkeleton::Error::InvalidEnvironmentError,
                "Value for required environment variable #{@name} not specified"
        end
      end
    end
  end
end
