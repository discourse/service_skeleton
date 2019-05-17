class ServiceSkeleton
  module BackgroundWorker
    include ServiceSkeleton::LoggingHelpers

    # async code is a shit to test, and rarely finds bugs anyway, so let's
    # just
    #:nocov:
    # this whole thing.

    # This signal is raised internally if needed to shut down a worker thread.
    class TerminateBackgroundThread < Exception; end
    private_constant :TerminateBackgroundThread

    def initialize(*_)
      @bg_worker_op_mutex = Mutex.new
      @bg_worker_op_cv    = ConditionVariable.new

      begin
        super
      rescue ArgumentError => ex
        if ex.message =~ /wrong number of arguments.*expected 0/
          super()
        else
          raise
        end
      end
    end

    def start!
      @bg_worker_op_mutex.synchronize do
        return if @bg_worker_thread

        @bg_worker_thread = Thread.new do
          Thread.current.name = self.class.to_s

          Thread.handle_interrupt(Exception => :never) do
            logger.debug("BackgroundWorker(#{self.class})#start!") { "Background worker thread #{Thread.current.object_id} starting" }
            begin
              Thread.handle_interrupt(Exception => :immediate) do
                @bg_worker_op_mutex.synchronize { @bg_worker_op_cv.signal }
                self.start
              end
            rescue TerminateBackgroundThread
              logger.debug("BackgroundWorker(#{self.class})#start!") { "Background worker thread #{Thread.current.object_id} received magical termination exception" }
            rescue Exception => ex
              log_exception(ex) { "Background worker thread #{Thread.current.object_id} received fatal exception" }
            else
              logger.debug("BackgroundWorker(#{self.class})#start!") { "Background worker thread #{Thread.current.object_id} terminating" }
            end
          end
          logger.debug("BackgroundWorker(#{self.class})#start!") { "Background worker thread #{Thread.current.object_id} is now done" }
        end

        @bg_worker_op_cv.wait(@bg_worker_op_mutex) until @bg_worker_thread
      end
    end

    def stop!(force = nil)
      @bg_worker_op_mutex.synchronize do
        return if @bg_worker_thread.nil?

        logger.debug("BackgroundWorker(#{self.class})#stop!") { "Terminating worker thread #{@bg_worker_thread.object_id} as requested" }

        if force == :force
          logger.debug(logloc) { "Forcing termination" }
          @bg_worker_thread.raise(TerminateBackgroundThread)
        else
          logger.debug(logloc) { "Gracefully terminating worker thread" }
          shutdown
        end

        begin
          logger.debug(logloc) { "Waiting for worker thread #{@bg_worker_thread.object_id} to finish itself off" }
          @bg_worker_thread.join unless @bg_worker_thread == Thread.current
        rescue TerminateBackgroundThread
          nil
        end

        @bg_worker_thread = nil

        logger.debug("BackgroundWorker(#{self.class})#stop!") { "Worker thread #{@bg_worker_thread.object_id} terminated" }
      end
    end

    private

    attr_reader :logger

    def shutdown
      logger.debug("BackgroundWorker(#{self.class})#stop!") { "Using default shutdown method" }
      @bg_worker_thread.raise(TerminateBackgroundThread) if @bg_worker_thread
    end
  end
end
