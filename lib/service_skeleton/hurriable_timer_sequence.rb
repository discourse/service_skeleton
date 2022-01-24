# frozen_string_literal: true

# HurribleTimerSequence is a resettable version of HurriableTimer, designed for
# cases where some action needs to happen at at least some frequency, but may
# happen more often when other threads trigger the process early.
#
# It would have been possible to implement this without requiring allocation on
# reset, by reusing the mutex and condition variable in the normal timer, but
# this version is more obviously correct.
class ServiceSkeleton::HurriableTimerSequence
  def initialize(timeout)
    @mutex = Mutex.new
    @timeout = timeout
    @latest = ServiceSkeleton::HurriableTimer.new(@timeout)
  end

  def reset!
    @mutex.synchronize {
      @latest.hurry!
      @latest = ServiceSkeleton::HurriableTimer.new(@timeout)
    }
  end

  def wait(t = nil)
    @mutex.synchronize { @latest }.wait(t)
  end

  def hurry!
    @mutex.synchronize { @latest }.hurry!
  end

  def expired?
    @mutex.synchronize { @latest }.expired?
  end
end
