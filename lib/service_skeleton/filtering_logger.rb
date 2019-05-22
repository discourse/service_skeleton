# frozen_string_literal: true

require 'logger'

module FilteringLogger
  attr_reader :filters

  def filters=(f)
    raise ArgumentError, "Must provide an array" unless f.is_a?(Array)

    @filters = f
  end

  def add(s, m = nil, p = nil, &blk)
    p ||= @progname

    if @filters && p
      @filters.each do |re, sev|
        if re === p
          if s < sev
            return true
          else
            # We force the severity to nil for this call to override
            # the logger's default severity filtering logic, because
            # messages without a severity are always logged
            return super(nil, m, p, &blk)
          end
        end
      end
    end

    super
  end

  alias log add
end

Logger.prepend(FilteringLogger)
