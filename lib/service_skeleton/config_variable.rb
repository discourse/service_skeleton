class ServiceSkeleton
  class ConfigVariable
    attr_reader :name

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

    def value(raw_val)
      @blk.call(raw_val)
    end
  end
end
