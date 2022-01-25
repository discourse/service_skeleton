# frozen_string_literal: true

# A mechanism for waiting until a timer expires or until another thread signals
# readiness.
class ServiceSkeleton::HurriableTimer
  def initialize(timeout)
    @mutex = Mutex.new
    @condition = ConditionVariable.new
    @end_time = now + timeout
    @hurried = false
  end

  # Wait for the timer to elapse
  #
  # Any number of threads can wait on the same HurriableTimer
  def wait(t = nil)
    end_time =
      if t
        [@end_time, now + t].min
      else
        @end_time
      end

    @mutex.synchronize {
      while true
        remaining = end_time - now

        if remaining < 0 || @hurried
          break
        else
          @condition.wait(@mutex, remaining)
        end
      end
    }

    nil
  end

  # Cause the timer to trigger early if it hasn't already expired
  #
  # This method is idempotent
  def hurry!
    @mutex.synchronize {
      @hurried = true
      @condition.broadcast
    }

    nil
  end

  def expired?
    @hurried || @end_time - now < 0
  end

  private

  def now
    # Using this instead of Time.now, because it isn't affected by NTP updates
    Process.clock_gettime(Process::CLOCK_MONOTONIC_RAW)
  end
end
