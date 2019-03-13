class ServiceSkeleton
  class ConfigVariable
    attr_reader :name, :key_pattern

    def initialize(name, **opts, &blk)
      @name = name
      @opts = opts
      @blk  = blk
    end

    def method_name(svc_name)
      name.to_s.gsub(/\A#{Regexp.quote(svc_name)}_/i, '').downcase
    end

    def sensitive?
      !!@opts[:sensitive]
    end

    def value(env)
      if @opts[:key_pattern]
        matches = env.select { |k, _| @opts[:key_pattern] === k.to_s }
        @blk.call(matches)
      else
        @blk.call(env[@name.to_s])
      end
    end

    def env_keys(env)
      if @opts[:key_pattern]
        env.keys.select { |k| @opts[:key_pattern] === k.to_s }
      else
        env.keys.include?(@name.to_s) ? [@name.to_s] : []
      end
    end
  end
end
