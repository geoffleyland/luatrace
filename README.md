# luatrace - tracing, profiling and coverage for Lua

## 1. What?

luatrace adds a layer on top of Lua's debug hooks to make it easier to collect
information for profiling and coverage analysis.

It collects a trace of every line executed, and can then analyse the trace to
provide time profile and coverage reports.

luatrace can trace through coroutine resumes and yields, and through xpcalls,
pcalls and errors.
On some platforms (OS X only) it uses high resolution timers to collect
times in the order of nanoseconds.

To use it run you code with `lua -luatrace <your lua file>` and then analyse it
with `luaprofile`

luatrace is brought to you by [Incremental](http://www.incremental.co.nz/) (<info@incremental.co.nz>)
and is available under the [MIT Licence](http://www.opensource.org/licenses/mit-license.php).


## 2. How?

luatrace is separated into to parts - the trace collector, and the backends that
record and process the traces.

The trace collector uses Lua's debug hooks and adds timing information and a
little bit of processing to make the traces easier to use.

Timing is provided one of three ways:

+ Lua - with a debug hook calling `os.clock`
+ LuaJIT - with a debug hook calling `ffi.C.clock` - `os.clock` is not yet
  implemented as a fast function
+ Lua - if the c_hook has been built then that's used instead of the Lua hook.
  The C uses the C library's `clock` and should call it closer to actual code
  execution, so the traces should be more accurate.
  On mach plaforms (ie OS X), the c_hook uses the `mach_absolute_time` high
  resolution timer for nanosecond resolution (but not accuracy)

The collector outputs traces by calling a recorder's `record` function.
This can be called in one of four ways, with up to 3 arguments:

+ `("S", <filename>, <line>)` - the trace has started somewhere in a function defined on line
+ `(">", <filename>, <line>)` - there's been a call to a function defined on line
+ `("<", <filename>, <line>)` - return from a function
+ `(<line>, <time in microseconds>)` - this many microseconds were just spent on this line of the current file

At the moment, there's two recorders - `luatrace.trace_file` and `luatrace.profile`.

`trace_file` is the default back-end.  It just writes the trace out to a file in a simple format,
which it can also read.  When it reads a file, it reads it to another recorder
as if the recorder were watching the program execute.

`profile` provides limited profile information.

Back ends will improve as I need them or as you patch/fork.


## 3. Requirements

Lua or LuaJIT.


## 4. Issues

+ It's really slow
+ It doesn't work with LuaJIT yet because I haven't worked out how to handle tail calls with LuaJIT
+ Times probably aren't accurate because of the time spent getting between user code and the hooks
+ There aren't many back-ends
+ I haven't done any work on the timing errors (ie how much "hook time" is recorded as execution time)


## 5. Alternatives

See [the Lua Wiki](http://lua-users.org/wiki/ProfilingLuaCode) for a list of profiling alternatives.
[luacov](http://luacov.luaforge.net/) provides coverage analysis.


