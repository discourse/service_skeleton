# frozen_string_literal: true

module ServiceSkeleton
  module ConfigClass
    Undefined = Module.new
    private_constant :Undefined

    def config_class(klass = Undefined)
      unless klass == Undefined
        @config_class = klass
      end

      @config_class
    end
  end
end
