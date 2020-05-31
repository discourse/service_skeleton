# frozen_string_literal: true

module ServiceSkeleton
  module SignalsMethods
    def registered_signal_handlers
      @registered_signal_handlers || []
    end

    def hook_signal(sigspec, &blk)
      @registered_signal_handlers ||= []

      @registered_signal_handlers << [sigspec, blk]
    end
  end
end
