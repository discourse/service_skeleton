> # WARNING WARNING WARNING
>
> This README is, at least in part, speculative fiction.  I practice
> README-driven development, and as such, not everything described in here
> actually exists yet, and what does exist may not work right.

Ultravisor is like a supervisor, but... *ULTRA*.  The idea is that you specify
objects to instantiate and run in threads, and then the Ultravisor makes that
happen behind the scenes, including logging failures, restarting if necessary,
and so on.  If you're familiar with Erlang supervision trees, then Ultravisor
will feel familiar to you, because I stole pretty much every good idea that
is in Ultravisor from Erlang.  You will get a lot of very excellent insight
from reading [the Erlang/OTP Supervision Principles](http://erlang.org/doc/design_principles/sup_princ.html).


# Installation

It's a gem:

    gem install ultravisor

There's also the wonders of [the Gemfile](http://bundler.io):

    gem 'ultravisor'

If you're the sturdy type that likes to run from git:

    rake install

Or, if you've eschewed the convenience of Rubygems entirely, then you
presumably know what to do already.


# Usage

This section gives you a basic overview of the high points of how Ultravisor
can be used.  It is not intended to be an exhaustive reference of all possible
options; the {Ultravisor} class API documentation provides every possible option
and its meaning.


## The Basics

Start by loading the code:

    require "ultravisor"

Creating a new Ultravisor is a matter of instantiating a new object:

    u = Ultravisor.new

In order for it to be useful, though, you'll need to add one or more children
to the Ultravisor instance, which can either be done as part of the call to
`.new`, or afterwards, as you see fit:

    # Defining a child in the constructor
    u = Ultravisor.new(children: [{id: :child, klass: Child, method: :run}])

    # OR define it afterwards
    u = Ultravisor.new
    u.add_child(id: :my_child, klass: Child, method: :run)

Once you have an Ultravisor with children configured, you can set it running:

    u.run

This will block until the Ultravisor terminates, one way or another.

We'll learn about other available initialization arguments, and all the other
features of Ultravisor, in the following sections.


## Defining Children

As children are the primary reason Ultravisor exists, it is worth getting a handle
on them first.

Defining children, as we saw in the introduction, can be done by calling
{Ultravisor#add_child} for each child you want to add, or else you can provide
a list of children to start as part of the {Ultravisor.new} call, using the
`children` named argument.  You can also combine the two approaches, if some
children are defined statically, while others only get added conditionally.

Let's take another look at that {Ultravisor#add_child} method from earlier:

    u.add_child(id: :my_child, klass: Child, method: :run)

First up, every child has an ID.  This is fairly straightforward -- it's a
unique ID (within a given Ultravisor) that refers to the child.  Attempting to
add two children with the same ID will raise an exception.

The `class` and `method` arguments require a little more explanation.  One
of the foundational principles of "fail fast" is "clean restart" -- that is, if you
do need to restart something, it's important to start with as clean a state as possible.
Thus, if a child needs to be restarted, we don't want to reuse an existing object, which
may be in a messy and unuseable state.  Instead, we want a clean, fresh object to work on.
That's why you specify a `class` when you define a child -- it is a new instance of that
class that will be used every time the child is started (or restarted).

The `method` argument might now be obvious.  Once the new instance of the
specified `class` exists, the Ultravisor will call the specified `method` to start
work happening.  It is expected that this method will ***not return***, in most cases.
So you probably want some sort of infinite loop.

You might think that this is extremely inflexible, only being able to specify a class
and a method to call.  What if you want to pass in some parameters?  Don't worry, we've
got you covered:

    u.add_child(
      id: :my_child,
      klass: Child,
      args: ['foo', 42, x: 1, y: 2],
      method: :run,
    )

The call to `Child.new` can take arbitrary arguments, just by defining an array
for the `args` named parameter.  Did you know you can define a hash inside an
array like `['foo', 'bar', x: 1, y: 2] => ['foo', 'bar', {:x => 1, :y => 2}]`?
I didn't, either, until I started working on Ultravisor, but you can, and it
works *exactly* like named parameters in method calls.

You can also add children after the Ultravisor has been set running:

    u = Ultravisor.new

    u.add_child(id: :c1, klass: SomeWorker, method: :run)

    u.run   # => starts running an instance of SomeWorker, doesn't return

    # In another thread...
    u.add_child(id: :c2, klass: OtherWorker, method: go!)

    # An instance of OtherWorker will be created and set running

If you add a child to an already-running Ultravisor, that child will immediately be
started running, almost like magic.


### Ordering of Children

The order in which children are defined is important.  When children are (re)started,
they are always started in the order they were defined.  When children are stopped,
either because the Ultravisor is shutting down, or because of a [supervision
strategy](#supervision-strategies), they are always stopped in the *reverse* order
of their definition.

All child specifications passed to {Ultravisor.new} always come first, in the
order they were in the array.  Any children defined via calls to
{Ultravisor#add_child} will go next, in the order the `add_child` calls were
made.


## Restarting Children

One of the fundamental purposes of a supervisor like Ultravisor is that it restarts
children if they crash, on the principle of "fail fast".  There's no point failing fast
if things don't get automatically fixed.  This is the default behaviour of all
Ultravisor children.

Controlling how children are restarted is the purpose of the "restart policy",
which is controlled by the `restart` and `restart_policy` named arguments in
the child specification.  For example, if you want to create a child that will
only ever be run once, regardless of what happens to it, then use `restart:
:never`:

    u.add_child(
      id: :my_one_shot_child,
      klass: Child,
      method: :run_maybe,
      restart: :never
    )

If you want a child which gets restarted if its `method` raises an exception,
but *not* if it runs to completion without error, then use `restart: :on_failure`:

    u.add_child(
      id: :my_run_once_child,
      klass: Child,
      method: :run_once,
      restart: :on_failure
    )

### The Limits of Failure

While restarting is great in general, you don't particularly want to fill your
logs with an endlessly restarting child -- say, because it doesn't have
permission to access a database.  To solve that problem, an Ultravisor will
only attempt to restart a child a certain number of times before giving up and
exiting itself.  The parameters of how this works are controlled by the
`restart_policy`, which is itself a hash:

    u.add_child(
      id: :my_restartable_child,
      klass: Child,
      method: :run,
      restart_policy: {
        period: 5,
        retries: 2,
        delay: 1,
      }
    )

The meaning of each of the `restart_policy` keys is best explained as part
of how Ultravisor restarts children.

When a child needs to be restarted, Ultravisor first waits a little while
before attempting the restart.  The amount of time to wait is specified
by the `delay` value in the `restart_policy`.  Then a new instance of the
`class` is instantiated, and the `method` is called on that instance.

The `period` and `retries` values of the `restart_policy` come into play
when the child exits repeatedly.  If a single child needs to be restarted
more than `retries` times in `period` seconds, then instead of trying to
restart again, Ultravisor gives up.  It doesn't try to start the child
again, it terminates all the *other* children of the Ultravisor, and
then it exits.  Note that the `delay` between restarts is *not* part
of the `period`; only time spent actually running the child is
accounted for.


## Managed Child Termination

If children need to be terminated, by default, child threads are simply
forcibly terminated by calling {Thread#kill} on them. However, for workers
which hold resources, this can cause problems.

Thus, it is possible to control both how a child is terminated, and how long
to wait for that termination to occur, by using the `shutdown` named argument
when you add a child (either via {Ultravisor#add_child}, or as part of the
`children` named argument to {Ultravisor.new}), like this:

    u.add_child(
      id: :fancy_worker,
      shutdown: {
        method: :gentle_landing,
        timeout: 30
      }
    )

When a child with a custom shutdown policy needs to be terminated, the
method named in the `method` key is called on the instance of `class` that
represents that child.  Once the shutdown has been signalled to the
worker, up to `timeout` seconds is allowed to elapse.  If the child thread has
not terminated by this time, the thread is forcibly terminated by calling
{Thread#kill}.  This timeout prevents shutdown or group restart from hanging
indefinitely.

Note that the `method` specified in the `shutdown` specification should
signal the worker to terminate, and then return immediately.  It should
*not* wait for termination itself.


## Supervision Strategies

When a child needs to be restarted, by default only the child that exited
will be restarted.  However, it is possible to cause other
children to be restarted as well, if that is necessary.  To do that, you
use the `strategy` named parameter when creating the Ultravisor:

    u = Ultravisor.new(strategy: :one_for_all)

The possible values for the strategy are:

* `:one_for_one` -- the default restart strategy, this simply causes the
  child which exited to be started again, in line with its restart policy.

* `:all_for_one` -- if any child needs to be restarted, all children of the
  Ultravisor get terminated in reverse of their start order, and then all
  children are started again, except those which are `restart: :never`, or
  `restart: :on_failure` which had not already exited without error.

* `:rest_for_one` -- if any child needs to be restarted, all children of
  the Ultravisor which are *after* the restarted child get terminated
  in reverse of their start order, and then all children are started again,
  except those which are `restart: :never`, or `restart: :on_failure` which
  had not already exited without error.


## Interacting With Child Objects

Since the Ultravisor is creating the object instances that run in the worker
threads, you don't automatically have access to the object instance itself.
This is somewhat by design -- concurrency bugs are hell.  However, there *are*
ways around this, if you need to.


### The power of cast / call

A common approach for interacting with an object in an otherwise concurrent
environment is the `cast` / `call` pattern.  From the outside, the interface
is quite straightforward:

```
u = Ultravisor.new(children: [
      { id: :castcall, klass: CastCall, method: :run, enable_castcall: true }
    ])

# This will return `nil` immediately
u[:castcall].cast.some_method

# This will, at some point in the future, return whatever `CastCall#to_s` could
u[:castcall].call.some_method
```

To enable `cast` / `call` support for a child, you must set the `enable_castcall`
keyword argument on the child.  This is because failing to process `cast`s and
`call`s can cause all sorts of unpleasant backlogs, so children who intend to
receive (and process) `cast`s and `call`s must explicitly opt-in.

The interface to the object from outside is straightforward.  You get a
reference to the instance of {Ultravisor::Child} for the child you want to talk
to (which is returned by {Ultravisor#add_child}, or {Ultravisor#[]}), and then
call `child.cast.<method>` or `child.call.<method>`, passing in arguments as
per normal.  Any public method can be the target of the `cast` or `call`, and you
can pass in any arguments you like, *including blocks* (although bear in mind that
any blocks passed will be run in the child instance's thread, and many
concurrency dragons await the unwary).

The difference between the `cast` and `call` methods is in whether or not a
return value is expected, and hence when the method call chained through
`cast` or `call` returns.

When you call `cast`, the real method call gets queued for later execution,
and since no return value is expected, the `child.cast.<method>` returns
`nil` immediately and your code gets on with its day.  This is useful
when you want to tell the worker something, or instruct it to do something,
but there's no value coming back.

In comparison, when you call `call`, the real method call still gets queued,
but the calling code blocks, waiting for the return value from the queued
method call.  This may seem pointless -- why have concurrency that blocks? --
but the value comes from the synchronisation.  The method call only happens
when the worker loop calls `process_castcall`, which it can do at a time that
suits it, and when it knows that nothing else is going on that could cause
problems.

One thing to be aware of when interacting with a worker instance is that it may
crash, and be restarted by the Ultravisor, before it gets around to processing
a queued message.  If you used `child.cast`, then the method call is just...
lost, forever.  On the other hand, if you used `child.call`, then an
{Ultravisor::ChildRestartedError} exception will be raised, which you can deal
with as you see fit.

The really interesting part is what happens *inside* the child instance.  The
actual execution of code in response to the method calls passed through `cast`
and `call` will only happen when the running instance of the child's class
calls `process_castcall`.  When that happens, all pending casts and calls will
be executed.  Since this happens within the same thread as the rest of the
child instance's code, it's a lot safer than trying to synchronise everything
with locks.

You can, of course, just call `process_castcall` repeatedly, however that's a
somewhat herp-a-derp way of doing it.  The `castcall_fd` method in the running
instance will return an IO object which will become readable whenever there is
a pending `cast` or `call` to process.  Thus, if you're using `IO.select` or
similar to wait for work to do, you can add `castcall_fd` to the readable set
and only call `process_castcall` when the relevant IO object comes back.  Don't
actually try *reading* from it yourself; `process_castcall` takes care of all that.

If you happen to have a child class whose *only* purpose is to process `cast`s
and `call`s, you should configure the Ultravisor to use `process_castcall_loop`
as its entry method.  This is a wrapper method which blocks on `castcall_fd`
becoming readable, and loops infinitely.

It is important to remember that not all concurrency bugs can be prevented by
using `cast` / `call`.  For example, read-modify-write operations will still
cause all the same problems they always do, so if you find yourself calling
`child.call`, modifying the value returned, and then calling `child.cast`
with that modified value, you're in for a bad time.


### Direct (Unsafe) Instance Access

If you have a worker class which you're *really* sure is safe against concurrent
access, you can eschew the convenience and safety of `cast` / `call`, and instead
allow direct access to the worker instance object.

To do this, specify `access: :unsafe` in the child specification, and then
call `child.unsafe_instance` to get the instance object currently in play.

Yes, the multiple mentions of `unsafe` are there deliberately, and no, I won't
be removing them.  They're there to remind you, always, that what you're doing
is unsafe.

If the child is restarting at the time `child.unsafe_instance` is called,
the call will block until the child worker is started again, after which
you'll get the newly created worker instance object.  The worker could crash
again at any time, of course, leaving you with a now out-of-date object
that is no longer being actively run.  It's up to you to figure out how to
deal with that.  If the Ultravisor associated with the child
has terminated, your call to `child.unsafe_instance` will raise an
{Ultravisor::ChildRestartedError}.

Why yes, Gracie, there *are* a lot of things that can go wrong when using
direct instance object access.  Still wondering why those `unsafe`s are in
the name?


## Supervision Trees

Whilst a collection of workers is a neat thing to have, more powerful systems
can be constructed if supervisors can, themselves, be supervised.  Primarily
this is useful when recovering from persistent errors, because you can use
a higher-level supervisor to restart an entire tree of workers which has one
which is having problems.

Creating a supervision tree is straightforward.  Because Ultravisor works by
instantiating plain old ruby objects, and Ultravisor is, itself, a plain old
ruby class, you use it more-or-less like you would any other object:

    u = Ultravisor.new
    u.add_child(id: :sub_sup, klass: Ultravisor, method: :run, args: [children: [...]])

That's all there is to it.  Whenever the parent Ultravisor wants to work on the
child Ultravisor, it treats it like any other child, asking it to terminate,
start, etc, and the child Ultravisor's work consists of terminating, starting,
etc all of its children.

The only difference in default behaviour between a regular worker child and an
Ultravisor child is that an Ultravisor's `shutdown` policy is automatically set
to `method: :stop!, timeout: :infinity`.  This is because it is *very* bad news
to forcibly terminate an Ultravisor before its children have stopped -- all
those children just get cast into the VM, never to be heard from again.


# Contributing

Bug reports should be sent to the [Github issue
tracker](https://github.com/mpalmer/ultravisor/issues), or
[e-mailed](mailto:theshed+ultravisor@hezmatt.org).  Patches can be sent as a
Github pull request, or [e-mailed](mailto:theshed+ultravisor@hezmatt.org).


# Licence

Unless otherwise stated, everything in this repo is covered by the following
copyright notice:

    Copyright (C) 2019  Matt Palmer <matt@hezmatt.org>

    This program is free software: you can redistribute it and/or modify it
    under the terms of the GNU General Public License version 3, as
    published by the Free Software Foundation.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
