The `ServiceSkeleton` provides the bare bones of a "service" program -- one
which is intended to be long-lived, providing some sort of functionality to
other parts of a larger system.  It provides:

* A Logger, including dynamic log-level and filtering management;
* Prometheus-based metrics registry;
* Signal handling;
* Configuration extraction from the process environment;
* and more.

The general philosophy of `ServiceSkeleton` is to provide features which have
been found to be almost universally necessary, in modern deployment
configurations, to prefer convenience over configuration, and to always be
secure by default.


# Installation

It's a gem:

    gem install service_skeleton

There's also the wonders of [the Gemfile](http://bundler.io):

    gem 'service_skeleton'

If you're the sturdy type that likes to run from git:

    rake install

Or, if you've eschewed the convenience of Rubygems entirely, then you
presumably know what to do already.


# Usage

A very minimal implementation of a service using `ServiceSkeleton`, which
simply prints "Hello, Service!" to stdout every second or so, might look
like this:

    require "service_skeleton"

    class HelloService < ServiceSkeleton
      def run
        loop do
          puts "Hello, Service!"
          sleep 1
        end
      end
    end

    HelloService.new(ENV).start if __FILE__ == $0

First, we require the `"service_skeleton"` library, which is a pre-requisite
for the `ServiceSkeleton` base class to be available, which is subclassed by
`HelloService`.  The `run` method is where you put your service's work,
typically in an infinite loop, because services are long-running, persistent
processes.

Finally, the last line instantiates an instance of our service (passing the
process environment in, for configuration), and then calls `.run` on that
object -- but only if we were called as a standalone program (rather than
being `require`'d ourselves).


## The `#run` loop

The core of a service is usually some sort of infinite loop, which waits for a
reason to do something, and then does it.  A lot of services are
network-accessible, and so the "reason to do something" is "because someone
made a connection to a port I'm listening".  Other times it could be because of
a periodic timer, a filesystem event, or anything else that takes your fancy.

Whatever it is, `ServiceSkeleton` doesn't discriminate.  All you have to do is
write it in your subclass' `#run` method, and `ServiceSkeleton` will take care
of the rest.

If your `#run` method exits, the service will terminate.


### STAHP!

Because the range of what a service can do is so broad, we can't provide a
generic way to stop your service.  You'll want to provide a (thread-safe)
`#shutdown` method, which will gracefully cause your `#run` method to clean up
its resources and return.  If you don't provide such a method, then the default
behaviour of `#shutdown` is to send an exception to the running thread, which
is somewhat brutal and prone to unpleasantness.  If your service wants to
cleanly exit of its own accord, it can also just return from the `#run` method,
and the service will terminate without any fuss.


### Exceptional Behaviour

If your `#run` loop happens to raise an unhandled exception, it will be caught,
logged, and the service will terminate.  `ServiceSkeleton` believes in the
value of "fail fast", and if an exception makes it all way out, then there's no
telling what has gone wrong or if it can be reasonably recovered.  The safest
option is to terminate the service process entirely, and have your service
supervisor start everything up again from scratch.


## The Service Name

Several aspects of a `ServiceSkeleton` service, including environment variable
and metric names, expect the service's name as a prefix by default.  The
service name is derived from the name of the class that subclasses
`ServiceSkeleton`, by converting the `CamelCase` class name into a `snake_case`
service name.  If the class name is in a namespace, that is included also, with
the `::` turned into `_`.


## Configuration

Almost every service has a need for some amount of configuration.  In keeping
with the general principles of the [12 factor app](https://12factor.net), the
`ServiceSkeleton` takes configuration from the environment.  However, we try to
minimise the amount of manual effort you need to expend to make that happen,
and provide configuration management as a first-class operation.


### Basic Configuration

Every `ServiceSkeleton` has an instance method defined, called `config`, which
returns an instance of `ServiceSkeleton::Config` (or some other class you
specify; more on that below), which provides access to the environment that was
passed into the service object at instantiation time (ie the `ENV` in
`MyService.new(ENV)`) via the `#[]` method.  So, in a very simple
application where you want to get the name of the thing to say hello to, it
might look like this:

    class GenericHelloService < ServiceSkeleton
      def run
        loop do
          puts "Hello, #{config["RECIPIENT"]}!"
          sleep 1
        end
      end
    end


### Variable Declaration

If your application has very minimal needs,  it's possible that directly
accessing the environment will be sufficient.  However, you can (and probably
should) declare your configuration variables in your service class, because
that way you can get coerced values (numbers and booleans, rather than strings
everywhere), range and format checking (say "the number must be between one and
ten", or "the string must match this regex"), default values, and error
reporting.  You also get direct access to the configuration value as a method
call on the `config` object.

To declare configuration variables, simply call one of the "config declaration
methods" (as listed in the `ServiceSkeleton::ConfigVariables` module) in your
class definition, and pass it an environment variable name (as a string or
symbol) and any relevant configuration parameters (like a default, or a
validity range, or whatever).

When your service object is instantiated, the environment will be examined and
the configuration setup.  If any values are invalid (number out of range, etc)
or missing (for any configuration variable that doesn't have a default), then
an error will be logged and the service will not start.

During your service's execution, any time you need to access a configuration
value, just call the matching method name (the all-lowercase version of the
environment variable name) on `config`, and you'll get the value in your
lap.

Here's a version of our generic greeter service, using declared configuration
variables:

    class GenericHelloService < ServiceSkeleton
      string :RECIPIENT, matches: /\A\w+\z/

      def run
        loop do
          puts "Hello, #{config.recipient}!"
          sleep 1
        end
      end
    end


### Environment Variable Prefixes

It's common for all (or almost all) of your environment variables to have a
common prefix, usually named for your service, so it's easy to identify your
service's configuration from anything else that's lying around.  However, you
don't want to have to use that prefix when accessing your `config` methods.

Enter: the service name prefix.  Any of your environment variables whose name
starts with [your service's name](#the-service-name) (matched
case-insensitively) followed by an underscore will have that part of the
environment variable name removed to determine the method name on `config`.
The *original* environment variable name is still matched to a variable
declaration, so, you need to declare the variable *with* the prefix, but the
method name won't have it.

Using this environment variable prefix support, the `GenericHelloService` would
have a (case-insensitive) prefix of `generic_hello_service_`.  In that case,
extending the above example a little more, you could do something like this:

    class GenericHelloService < ServiceSkeleton
      string :GENERIC_HELLO_SERVICE_RECIPIENT, matches: /\A\w+\z/

      def run
        loop do
          puts "Hello, #{config.recipient}!"
          sleep 1
        end
      end
    end

Then, if the environment contained `GENERIC_HELLO_SERVICE_RECIPIENT`, its value
would be accessible via `config.recipient` in the program.


### Sensitive environment variables

Sometimes your service will take configuration data that really, *really*
shouldn't be available to subprocesses or anyone who manages to catch a
sneak-peek at your service's environment.  In that case, you can declare an
environment variable as "sensitive", and after the configuration is parsed,
that environment variable will be wiped from the environment.

To declare an environment variable as "sensitive", simply pass the `sensitive`
parameter, with a trueish value, to the variable declaration in your class:

    class DatabaseManager < ServiceSkeleton
      string :DB_PASSWORD, sensitive: true

      ...
    end

> **NOTE**: The process environment can only be modified if you pass the real,
> honest-to-goodness `ENV` object into `MyServiceClass.new(ENV)`.  If you
> provide a copy, or some other hash, that'll work *normally*, but if you have
> sensitive variables, the service will log an error and refuse to start.  This
> avoids the problems of accidentally modifying global state if that would be
> potentially bad (we assume you copied `ENV` for a reason) without leaving a
> gaping security hole (sensitive data blindly passed into subprocesses that
> you didn't expect).


### Custom Configuration Class

Whilst we hope that `ServiceSkeleton::Config`  class will be useful in most
situations, there are undoubtedly cases where the config management we provide
won't be enough.  In that case, you are encouraged to subclass
`ServiceSkeleton::Config` and augment the standard interface with your own
implementations (remembering to call `super` where appropriate), and tell
`ServiceSkeleton` to use your implementation by calling the `.config_class`
class method in your service's class definition, like this:

    class MyServiceConfig < ServiceSkeleton::Config
      attr_reader :something_funny

      def initialize(env)
        @something_funny = "flibbety gibbets"
      end
    end

    class MyService < ServiceSkeleton
      config_class MyServiceConfig

      def run
        loop do
          puts config.something_funny
          sleep 1
        end
      end
    end


## Logging

You can't have a good service without good logging.  Therefore, the
`ServiceSkeleton` does its best to provide a sensible logging implementation
for you to use.


### What You Get

Every instance of your service class (as subclassed from `ServiceSkeleton`)
has a method named, uncreatively, `logger`.  It is a (more-or-less) straight-up
instance of the Ruby stdlib `Logger`, on which you can call all the usual
methods (`#debug`, `#info`, `#warn`, `#error`, etc).  By default, it sends all
log messages to standard error.

When calling the logger, you really, *really* want to use the
"progname+message-in-a-block" style of recording log messages, which looks like
this:

    logger.debug("lolrus") { "Something funny!" }

In addition to the potential performance benefits, the `ServiceSkeleton` logger
provides the ability to filter on the progname passed to each log message call.
That means that you can put in *lots* of debug logging (which is always a good
idea), and then turn on debug logging *only* for the part of the system you
wish to actively debug, based on log messages that are tagged with a specified
progname.  No more grovelling through thousands of lines of debug logging to
find the One Useful Message.

The `ServiceSkeleton` also provides built-in dynamic log level adjustment;
using Unix signals or the admin HTTP interface (if enabled), you can tell the
logger to increase or decrease logging verbosity *without interrupting
service*.  We are truly living in the future.

Finally, if you're a devotee of the ELK stack, we can automagically send log
entries straight into logstash, rather than you having to do it in some
more roundabout fashion.


### Logging Configuration

The logger automatically sets its configuration from, you guessed it, the
environment.  The following environment variables are recognised by the logger.
All are all-uppercase, and the `<SERVICENAME>_` portion is the all-uppercase
[service name](#the-service-name).

* **`<SERVICENAME>_LOG_LEVEL`** (default: `"INFO"`) -- the minimum severity of
  log messages which will be emitted by the logger.

  The simple form of this setting is just a severity name: one of `DEBUG`,
  `INFO`, `WARN`, `ERROR`, or `FATAL` (case-insensitive).  This sets the
  severity threshold for all log messages in the entire service.

  If you wish to change the severity level for a single progname, you can
  override the default log level for messages with a specific progname, by
  specifying one or more "progname severities" separated by commas.  A progname
  severity looks like this:

        <progname>=<severity>

  To make things even more fun, if `<progname>` looks like a regular expression
  (starts with `/` or `%r{`, and ends with `/` or `}` plus optional flag
  characters), then all log messages with prognames *matching* the specified
  regexp will have that severity applied.  First match wins.  The default is
  still specified as a bare severity name, and the default can only be set
  once.

  That's a lot to take in, so here's an example which sets the default to `INFO`,
  debugs the `buggy` progname, and only emits errors for messages with the
  (case-insensitive) string `noisy` in their progname:

        INFO,buggy=DEBUG,/noisy/i=ERROR

  Logging levels can be changed at runtime, via [signals](#default-signals) or
  [the HTTP admin interface](#http-admin-interface).

* **`<SERVICENAME>_LOGSTASH_SERVER`** (string; default `""`) -- if set to a
  non-empty string, we will engage the services of the [loggerstash
  gem](https://github.com/discourse/loggerstash) on your behalf to send all log
  entries to the logstash server you specify (as [an `address:port`,
  `hostname:port`, or SRV
  record](https://github.com/discourse/logstash_writer#usage).  Just be sure
  and [configure logstash
  appropriately](https://github.com/discourse/loggerstash#logstash-configuration).

* **`<SERVICENAME>_LOG_ENABLE_TIMESTAMPS`** (boolean; default: `"no"`) -- if
  set to a true-ish value (`yes`/`y`/`on`/`true`/`1`), then the log entries
  emitted by the logger will have the current time (to the nearest nanosecond)
  prefixed to them, in RFC3339 format
  (`<YYYY>-<mm>-<dd>T<HH>:<MM>:<SS>.<nnnnnnnnn>Z`).  By default, it is assumed
  that services are run through a supervisor system of some sort, which
  captures log messages and timestamps them, but if you are in a situation
  where log messages aren't automatically timestamped, then you can use this to
  get them back.

* **`<SERVICENAME>_LOG_FILE`** (string; default: `"/dev/stderr`) -- the file to
  which log messages are written.  The default, to send messages to standard
  error, is a good choice if you are using a supervisor system which captures
  service output to its own logging system, however if you are stuck without
  such niceties, you can specify a file on disk to log to instead.

* **`<SERVICENAME>_LOG_MAX_FILE_SIZE`** (integer; range 0..Inf; default:
  `"1048576"`) -- if you are logging to a file on disk, you should limit the
  size of each log file written to prevent disk space exhaustion.  This
  configuration variable specifies the maximum size of any one log file, in
  bytes.  Once the log file exceeds the specified size, it is renamed to
  `<filename>.0`, and a new log file started.

  If, for some wild reason, you don't wish to limit your log file sizes, you
  can set this environment variable to `"0"`, in which case log files will
  never be automatically rotated.  In that case, you are solely responsible for
  rotation and log file management, and [the `SIGHUP` signal](#default-signals)
  will likely be of interest to you.

* **`<SERVICENAME>_LOG_MAX_FILES`** (integer; range 1..Inf; default: `"3"`) --
  if you are logging to a file on disk,  you should limit the number of log
  files kept to prevent disk space exhaustion.  This configuration variable
  specifies the maximum number of log files to keep (including the log file
  currently being written to).  As log files reach `LOG_MAX_FILE_SIZE`, they
  are rotated out, and older files are renamed with successively higher numeric
  suffixes.  Once there are more than `LOG_MAX_FILES` on disk, the oldest file
  is deleted to keep disk space under control.

  Using this "file size+file count" log file management method, your logs will
  only ever consume about `LOG_MAX_FILES*LOG_MAX_FILE_SIZE` bytes of disk
  space.


## Metrics

Running a service without metrics is like trying to fly a fighter jet whilst
blindfolded.  Everything seems to be going OK until you slam into the side of a
mountain you never saw coming.  For that reason, `ServiceSkeleton` provides a
Prometheus-based metrics registry, a bunch of default process-level metrics, an
optional HTTP metrics server, and simple integration with [the Prometheus ruby
client library](https://rubygems.org/gems/prometheus-client) and [the
Frankenstein library](https://rubygems.org/gems/frankenstein) to make it as
easy as possible to instrument the heck out of your service.


### Defining and Using Metrics

All the metrics you want to use within your service need to be registered
before use.  This is typically done in the `#run` method, before entering the
infinite loop.

To register a metric, use one of the standard metric registration methods from
[Prometheus::Client::Registry](https://www.rubydoc.info/gems/prometheus-client/0.8.0/Prometheus/Client/Registry)
(`#counter`, `#gauge`, `#histogram`, `#summary`, or `#register`) on the `metrics`
object to create or register the metric.

In our generic greeter service we've been using as an example so far, you might
like to define a metric to count how many greetings have been sent.  You'd define
such a metric like this:

    class GenericHelloService < ServiceSkeleton
      string :GENERIC_HELLO_SERVICE_RECIPIENT, matches: /\A\w+\z/

      def run
        metrics.counter(:greetings_total, "How many greetings we have sent")

        loop do
          puts "Hello, #{config.recipient}!"
          sleep 1
        end
      end
    end

When it comes time to actually *use* the metrics you have created, it's typical
to keep a copy of the metric object laying around, or call `metrics.get`.  However,
we make it easier to access your metrics, by defining a method named for the metric
on `metrics`.  Thus, to increment our greeting counter, you can simply do:

    class GenericHelloService < ServiceSkeleton
      string :GENERIC_HELLO_SERVICE_RECIPIENT, matches: /\A\w+\z/

      def run
        metrics.counter(:greetings_total, "How many greetings we have sent")

        loop do
          puts "Hello, #{config.recipient}!"
          metrics.greetings_total.increment(recipient: config.recipient)
          sleep 1
        end
      end
    end

As a bonus, because metric names are typically prefixed with the service name,
any metrics you define which have the [service name](#the-service-name) as a
prefix will have that prefix (and the immediately-subsequent underscore) removed
before defining the metric accessor method, which keeps typing to a minimum:

    class GenericHelloService < ServiceSkeleton
      string :GENERIC_HELLO_SERVICE_RECIPIENT, matches: /\A\w+\z/

      def run
        metrics.counter(:generic_hello_service_greetings_total, "How many greetings we have sent")

        loop do
          puts "Hello, #{config.recipient}!"
          metrics.greetings_total.increment(recipient: config.recipient)
          sleep 1
        end
      end
    end


### Default Metrics

[Recommended
practice](https://prometheus.io/docs/instrumenting/writing_clientlibs/#standard-and-runtime-collectors)
is for collectors to provide a bunch of standard metrics, and `ServiceSkeleton`
never met a recommended practice it didn't like.  So, we provide [process
metrics](https://www.rubydoc.info/gems/frankenstein/Frankenstein/ProcessMetrics),
[Ruby GC
metrics](https://www.rubydoc.info/gems/frankenstein/Frankenstein/RubyGCMetrics),
and [Ruby VM
metrics](https://www.rubydoc.info/gems/frankenstein/Frankenstein/RubyVMMetrics).


### Metrics Server Configuration

Whilst metrics are always collected, they're not very useful unless they can
be scraped by a server.  To enable that, you'll need to look at the following
configuration variables.  All metrics configuration environment variables are
all-uppercase, and the `<SERVICENAME>_` portion is the all-uppercase version
of [the service name](#the-service-name).

* **`<SERVICENAME>_METRICS_PORT`** (integer; range 1..65535; default: `""`) --
  if set to a non-empty integer which is a valid port number (`1` to `65535`,
  inclusive), an HTTP server will be started which will respond to a request to
  `/metrics` with a Prometheus-compatible dump of time series data.


## Signal Handling

Whilst they're a bit old-fashioned, there's no denying that signals still have
a useful place in the arsenal of a modern service.  However, there are some
caveats that apply to signal handling (like their habit of interrupting at
inconvenient moments when you can't use mutexes).  For that reason, the
`ServiceSkeleton` comes with a signal watcher, which converts specified incoming
signals into invocations of regular blocks of code, and a range of default
behaviours for common signals.


### Default Signals

When the `#run` method on your service instance is called, the following
signals will be hooked with the following behaviour:

* **`SIGUSR1`** -- increase the default minimum severity for messages which
  will be emitted by the logger.  The default severity only applies to log
  messages whose progname does not match a "progname specifier" (see "[Logging
  Configuration](#logging-configuration)").

* **`SIGUSR2`** -- decrease the default minimum severity for messages which
  will be emitted by the logger.

* **`SIGHUP`** -- close and reopen the log file, if logging to a file on disk.
  Because of the `ServiceSkeleton`'s default log rotation policy, this shouldn't
  ordinarily be required, but if you've turned off the default log rotation,
  you may need tis.

* **`SIGQUIT`** -- dump a *whooooooole* lot of debugging information to
  standard error, including memory allocation summaries and stack traces of all
  running threads.  If you've ever sent `SIGQUIT` a Java program, or
  `SIGABRT` to a golang program, you know how handy this can be in certain
  circumstances.

* **`SIGINT`** / **`SIGTERM`** -- ask the service to gracefully stop running.
  It will call your service's `#shutdown` method to ask it to stop what it's
  doing and exit.  If the signal is sent twice, your run method will be
  summarily terminated and everything will be terminated quickly.  As usual, if
  a service process needs to be whacked completely and utterly *right now*,
  `SIGKILL` is what you want to use.


### Hooking Signals

In addition to the above default signal dispositions, you can also hook signals
yourself for whatever purpose you desire.  This is typically done in your
`#run` method, before entering the infinite loop.

To hook a signal, just call `hook_signal` with a signal specification and a
block of code to execute when the signal fires.  You can even hook the same
signal more than once, because the signal handlers that `SkeletonService` uses
chain to other signal handlers.  As an example, if you want to print "oof!"
every time the `SIGCONT` signal is received, you'd do something like this:

    class MyService < ServiceSkeleton
      def run
        hook_signal("CONT") { puts "oof!" }

        loop { sleep }
      end
    end

When the service is shutdown, all signal handlers will be automatically
unhooked, which saves you having to do it yourself.

> **NOTE**: You can define a maximum of 256 signal hooks in a single service,
> including the default signal hooks.


## HTTP Admin Interface

In these modern times we live in, it seems everything from nuclear reactors to
toasters can be controlled from a browser.  Why should your services be any
different?


### HTTP Admin Configuration

In the spirit of "secure by default", you must explicitly enable the HTTP admin
interface, and it requires authentication.  To do that, use the following
environment variables, where `<SERVICENAME>_` is the all-uppercase version of
[the service name](#the-service-name).

* **`<SERVICENAME>_HTTP_ADMIN_PORT`** (integer; range 1..65535; default: `""`)
  -- if set to a valid port number (`1` to `65535` inclusive), the HTTP admin
  interface will listen on that port, if also enabled by configuring
  authentication.

* **`<SERVICENAME>_HTTP_ADMIN_BASIC_AUTH`** (string; default: `""`) -- if set
  to a string containing a username and password separated by a colon, then
  authentication via [HTTP Basic auth](https://tools.ietf.org/html/rfc7617)
  will be supported.  Note that in addition to this setting, an admin port must
  also be specified in order for the admin interface to be enabled.

* **`<SERVICENAME>_HTTP_ADMIN_PROXY_USERNAME_HEADER`** (string; default: `""`)
  -- if set to a non-empty string, then incoming requests will be examined for
  a HTTP header with the specified name.  If such a header exists and has a
  non-empty value, then the request will be deemed to have been authenticated
  by an upstream authenticating proxy (such as
  [`discourse-auth-proxy`](https://github.com/discourse/discourse-auth-proxy))
  as the user given in the header value.  Note that in addition to this
  setting, an admin port must also be specified in order for the admin
  interface to be enabled.


### HTTP Admin Features

* Visiting the service's `IP address:port` in a web browser will bring up an HTML
  interface showing all the features that are available.  Usage should
  (hopefully) be self-explanatory.

* Visiting the service's `IP address:port` whilst accepting `application/json`
  responses will provide a directory of links to available endpoints which you
  can use to interact with the HTTP admin interface programmatically.


# Contributing

Patches can be sent as [a Github pull
request](https://github.com/discourse/service_skeleton).  This project is
intended to be a safe, welcoming space for collaboration, and contributors
are expected to adhere to the [Contributor Covenant code of
conduct](CODE_OF_CONDUCT.md).


# Licence

Unless otherwise stated, everything in this repo is covered by the following
copyright notice:

    Copyright (C) 2018  Civilized Discourse Construction Kit, Inc.

    This program is free software: you can redistribute it and/or modify it
    under the terms of the GNU General Public License version 3, as
    published by the Free Software Foundation.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
