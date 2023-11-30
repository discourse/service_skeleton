# frozen_string_literal: true
class Ultravisor::Child::CastReceiver < BasicObject
  def initialize(&blk)
    @blk = blk
  end

  def method_missing(name, *args, **kwargs, &blk)
    castback = ::Ultravisor::Child::Cast.new(name, args, kwargs, blk)
    @blk.call(castback)
  end
end
