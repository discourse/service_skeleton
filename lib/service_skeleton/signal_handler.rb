require_relative "./background_worker"
require_relative "./logging_helpers"

class ServiceSkeleton
  # Manage signals in a sane and safe manner.
  #
  # Signal handling is a shit of a thing.  The code that runs when a signal is
  # triggered can't use mutexes (which are used in all sorts of places you
  # might not expect, like Logger!) or anything else that might block.  This
  # greatly constrains what you can do inside a signal handler, so the standard
  # approach is to stuff a character down a pipe, and then have the *real*
  # signal handling run later.
  #
  # Also, there's always the (slim) possibility that something else might have
  # hooked into a signal we want to receive.  Because only a single signal
  # handler can be active for a given signal at a time, we need to "chain" the
  # existing handler, by calling the previous signal handler from our signal
  # handler after we've done what we need to do.  This class takes care of
  # that, too, because it's a legend.
  #
  # So that's what this class does: it allows you to specify signals and
  # associated blocks of code to run, it sets up signal handlers which send
  # notifications to a background thread and chain correctly, and it manages
  # the background thread to receive the notifications and execute the
  # associated blocks of code outside of the context of the signal handler.
  #
  class SignalHandler
    include ServiceSkeleton::LoggingHelpers
    include ServiceSkeleton::BackgroundWorker

    # Setup a signal handler instance.
    #
    # A single signal handler instance can handle up to 256 hooks, potentially
    # hooking the same signal more than once.  Use #hook_signal to register
    # signal handling callbacks.
    #
    # @param logger [Logger] the logger to use for all the interesting information
    #   about what we're up to.
    #
    def initialize(logger:, service:, signal_counter:)
      @logger, @service, @signal_counter = logger, service, signal_counter

      @signal_registry = []

      super
    end

    #:nocov:

    # Register a callback to be executed on the receipt of a specified signal.
    #
    # @param sig [String, Symbol, Integer] the signal to hook into.  Anything that
    #   `Signal.trap` will accept is OK by us, too.
    #
    # @param blk [Proc] the code to run when the signal is received.
    #
    # @return [void]
    #
    # @raise [RuntimeError] if you try to create more than 256 signal hooks.
    #
    # @raise [ArgumentError] if `sig` isn't recognised as a valid signal
    #   specifier by `Signal.trap`.
    #
    def hook_signal(sig, &blk)
      @bg_worker_op_mutex.synchronize do
        handler_num = @signal_registry.length

        if handler_num > 255
          raise RuntimeError,
                "Signal hook limit reached.  Slow down there, pardner"
        end

        sigspec = { signal: sig, callback: blk }

        if @bg_worker_thread
          install_handler(sigspec, handler_num)
        else
          # If the background thread isn't running yet, the signal handler will
          # be installed when that is started.
        end

        @signal_registry << sigspec
      end
    end

    def start
      logger.info("SignalHandler#start") { "Starting signal handler with #{@signal_registry.length} hooks" }

      @r, @w = IO.pipe

      install_signal_handlers

      loop do
        begin
          if ios = IO.select([@r])
            if ios.first.include?(@r)
              if ios.first.first.eof?
                logger.info("SignalHandler#run") { "Signal pipe closed; shutting down" }
                break
              else
                c = ios.first.first.read_nonblock(1)
                handle_signal(c)
              end
            else
              logger.error("SignalHandler#run") { "Mysterious return from select: #{ios.inspect}" }
            end
          end
        rescue StandardError => ex
          log_exception(ex) { "Exception in select loop" }
        end
      end
    end

    private

    attr_reader :logger

    # Given a character (presumably) received via the signal pipe, execute the
    # associated handler.
    #
    # @param char [String] a single character, corresponding to an entry in the
    #   signal registry.
    #
    # @return [void]
    #
    def handle_signal(char)
      handler = @signal_registry[char.ord]

      if handler
        logger.debug("SignalHandler#handle_signal") { "#{handler[:signal]} received" }
        @signal_counter.increment(signal: handler[:signal].to_s)
        begin
          handler[:callback].call
        rescue => ex
          log_exception(ex) { "Exception in signal handler" }
        end
      else
        logger.error("SignalHandler#handle_signal") { "Unrecognised signal character: #{char.inspect}" }
      end
    end

    def install_signal_handlers
      @signal_registry.each_with_index do |sigspec, i|
        install_handler(sigspec, i)
      end
    end

    def install_handler(sigspec, i)
      chain = nil

      p = ->(_) do
        @w.write_nonblock(i.chr) rescue nil
        chain.call if chain.respond_to?(:call)
      end
      chain = Signal.trap(sigspec[:signal], &p)

      sigspec[:chain] = chain
      sigspec[:handler] = p
    end

    def shutdown
      uninstall_signal_handlers

      @r.close
    end

    def uninstall_signal_handlers
      @signal_registry.reverse.each do |sigspec|
        tmp_sig = Signal.trap(sigspec[:signal], "IGNORE")
        if tmp_sig == sigspec[:handler]
          # The current handler is ours, so we can replace
          # it with the chained handler
          Signal.trap(sigspec[:signal], sigspec[:chain])
        else
          # The current handler *isn't* this one, so we better
          # put it back, because whoever owns it might get
          # angry.
          Signal.trap(sigspec[:signal], tmp_sig)
        end
      end
    end
  end
end
