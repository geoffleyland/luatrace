# luatrace - tracing, profiling and coverage for Lua

## 1. What?

luatrace is a Lua module that collects information about what your code is doing
and how long it takes, and can analyse that information to generate profile and
coverage reports.

luatrace adds a layer on top of Lua's debug hooks to make it easier to collect
information for profiling and coverage analysis.
luatrace traces of every line executed, not just calls.

luatrace can trace through coroutine resumes and yields, and through xpcalls,
pcalls and errors.
On some platforms (OS X only) it uses high resolution timers to collect
times in the order of nanoseconds.

To use it, install luatrace with `sudo make install`,
run your code with `lua -luatrace <your lua file>` and then analyse it
with `luatrace.profile`.  The profiler will display a list of the top 20 functions
by time, and write a copy of all the source traced annotated with times for each
line.

Alternatively, you can `local luatrace = require("luatrace")` and surround the code
you wish to trace with `luatrace.tron()` and `luatrace.troff()`.

If you wish to use the profiler directly rather than on a trace file you can use
`lua -luatrace.profile <your lua file>` or `local luatrace = require("luatrace.profile")`.

luatrace runs under "plain" Lua and LuaJIT with the -joff option (LuaJIT doesn't
call hooks in compiled code, and luatrace loses track of where it's up to)

luatrace is brought to you by [Incremental](http://www.incremental.co.nz/) (<info@incremental.co.nz>)
and is available under the [MIT Licence](http://www.opensource.org/licenses/mit-license.php).


## 2. How?

luatrace is separated into two parts - the trace collector, and the backends that
record and process the traces.

The trace collector uses Lua's debug hooks and adds timing information and a
little bit of processing to make the traces easier to use.

Timing is provided one of three ways:

+ Lua - with a debug hook calling `os.clock`
+ LuaJIT - with a debug hook calling `ffi.C.clock` - `os.clock` is not yet
  implemented as a fast function
+ Lua and LuaJIT - if the c_hook has been built then that's used instead of the
  Lua or LuaJIT hook.  It's always better to use the C hook.
  The hook uses the C library's `clock` and should call it closer to actual code
  execution, so the traces should be more accurate.
  On mach plaforms (ie OS X), the c_hook uses the `mach_absolute_time` high
  resolution timer for nanosecond resolution (but be careful - although the
  timing is collected at nanosecond resolution, there are many reasons why
  profiles are not accurate to within a nanosecond!)

The collector outputs traces by calling a recorder's `record` function with a
range of arguments:

+ `("S", <filename>, <line>)` - the trace has started somewhere in a function defined on line
+ `(">", <filename>, <line>)` - there's been a call to a function defined on line
+ `("T", <filename>, <line>)` - there's been a tailcall to a function defined on line (LuaJIT only)
+ `("<")` - return from a function
+ `("R", <thread_id>)` - Resume the thread thread_id
+ `("Y")` - Yield
+ `("P")` - pcall - the current line is protected for the duration of the following call
+ `("E")` - Error - unwind the stack looking for a "P"
+ `(<line>, <time in microseconds>)` - this many microseconds were just spent on this line of the current file

At the moment, there's two recorders - `luatrace.trace_file` and `luatrace.profile`.

`trace_file` is the default backend.  It just writes the trace out to a file in a simple format,
which it can also read.  When it reads a file, it reads it to another recorder
as if the recorder were watching the program execute.

`profile` provides limited profile information.

Backends will improve as I need them or as you patch/fork.


## 3. Requirements

Lua or LuaJIT.


## 4. Issues

+ It's _really_ slow
+ Tracing is overcomplicated and has to check the stack depth too frequently
+ Profiling is very complicated when there's a lot on one line (one line functions)
+ Times probably aren't accurate because of the time spent getting between user code and the hooks
+ There aren't many back-ends


## 5. Wishlist

+ More of the hook should be in C
+ It would be nice if the recorder was in a separate Lua state and a separate thread
+ High-resolution timers on other platforms


## 6. Alternatives

See [the Lua Wiki](http://lua-users.org/wiki/ProfilingLuaCode) for a list of profiling alternatives.
[luacov](http://luacov.luaforge.net/) provides coverage analysis.


