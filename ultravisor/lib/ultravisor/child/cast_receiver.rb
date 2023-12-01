# frozen_string_literal: true
class Ultravisor::Child::CastReceiver < BasicObject
  def initialize(&blk)
    @blk = blk
  end

  def method_missing(name, *args, &blk)
    castback = ::Ultravisor::Child::Cast.new(name, args, blk)
    @blk.call(castback)
  end
  ruby2_keywords :method_missing if respond_to?(:ruby2_keywords, true)
end
