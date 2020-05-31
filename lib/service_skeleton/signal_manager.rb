# frozen_string_literal: true

require_relative "./logging_helpers"

module ServiceSkeleton
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
  class SignalManager
    include ServiceSkeleton::LoggingHelpers

    # Setup a signal handler instance.
    #
    # @param logger [Logger] the logger to use for all the interesting information
    #   about what we're up to.
    #
    def initialize(logger:, counter:, signals:)
      @logger, @signal_counter, @signal_list = logger, counter, signals

      @registry = Hash.new { |h, k| h[k] = SignalHandler.new(k) }

      @signal_list.each do |sig, proc|
        @registry[signum(sig)] << proc
      end
    end

    def run
      logger.info(logloc) { "Starting signal manager for #{@signal_list.length} signals" }

      @r, @w = IO.pipe

      install_signal_handlers

      signals_loop
    ensure
      remove_signal_handlers
    end

    def shutdown
      @r.close
    end

    private

    attr_reader :logger

    def signals_loop
      #:nocov:
      loop do
        begin
          if ios = IO.select([@r])
            if ios.first.include?(@r)
              if ios.first.first.eof?
                logger.info(logloc) { "Signal pipe closed; shutting down" }
                break
              else
                c = ios.first.first.read_nonblock(1)
                logger.debug(logloc) { "Received character #{c.inspect} from signal pipe" }
                handle_signal(c)
              end
            else
              logger.error(logloc) { "Mysterious return from select: #{ios.inspect}" }
            end
          end
        rescue IOError
          # Something has gone terribly wrong here... bail
          break
        rescue StandardError => ex
          log_exception(ex) { "Exception in select loop" }
        end
      end
      #:nocov:
    end

    # Given a character (presumably) received via the signal pipe, execute the
    # associated handler.
    #
    # @param char [String] a single character, corresponding to an entry in the
    #   signal registry.
    #
    # @return [void]
    #
    def handle_signal(char)
      if @registry.has_key?(char.ord)
        handler = @registry[char.ord]
        logger.debug(logloc) { "#{handler.signame} received" }
        @signal_counter.increment(signal: handler.signame.to_s)

        begin
          handler.call
        rescue StandardError => ex
          log_exception(ex) { "Exception while calling signal handler" }
        end
      else
        logger.error(logloc) { "Unrecognised signal character: #{char.inspect}" }
      end
    end

    def install_signal_handlers
      @registry.values.each do |h|
        h.write_pipe = @w
        h.hook
      end
    end

    def signum(spec)
      if spec.is_a?(Integer)
        return spec
      end

      if spec.is_a?(Symbol)
        str = spec.to_s
      elsif spec.is_a?(String)
        str = spec.dup
      else
        raise ArgumentError,
              "Unsupported class (#{spec.class}) of signal specifier #{spec.inspect}"
      end

      str.sub!(/\ASIG/i, '')

      if Signal.list[str.upcase]
        Signal.list[str.upcase]
      else
        raise ArgumentError,
              "Unrecognised signal specifier #{spec.inspect}"
      end
    end

    def remove_signal_handlers
      @registry.values.each { |h| h.unhook }
    end

    class SignalHandler
      attr_reader :signame
      attr_writer :write_pipe

      def initialize(signum)
        @signum = signum
        @callbacks = []

        @signame = Signal.list.invert[@signum]
      end

      def <<(proc)
        @callbacks << proc
      end

      def call
        @callbacks.each { |cb| cb.call }
      end

      def hook
        @handler = ->(_) do
          #:nocov:
          @write_pipe.write_nonblock(@signum.chr) rescue nil
          @chain.call if @chain.respond_to?(:call)
          #:nocov:
        end

        @chain = Signal.trap(@signum, &@handler)
      end

      def unhook
        #:nocov:
        tmp_handler = Signal.trap(@signum, "IGNORE")
        if tmp_handler == @handler
          # The current handler is ours, so we can replace it
          # with the chained handler
          Signal.trap(@signum, @chain)
        else
          # The current handler *isn't* ours, so we better
          # put it back, because whoever owns it might get
          # angry.
          Signal.trap(@signum, tmp_handler)
        end
        #:nocov:
      end
    end

    private_constant :SignalHandler
  end
end
