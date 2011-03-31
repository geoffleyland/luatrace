# luatrace - tracing, profiling and coverage for Lua

## 1. What?

luatrace adds a layer on top of Lua's debug hooks to make it easier to collect
information for profiling and coverage.
It collects traces of every line executed, and can then analyse those traces to
provide time profiles and coverage reports (not yet implemented).

To use it run you code with `lua -luatrace <your lua file>` and then analyse it with `luaprofile`

luatrace is brought to you by [Incremental](http://www.incremental.co.nz/) (<info@incremental.co.nz>)
and is available under the [MIT Licence](http://www.opensource.org/licenses/mit-license.php).


## 2. How?

luatrace is separated into to parts - the trace collector, and the backends that
record and process the traces.

The trace collector uses Lua's debug hooks and adds timing information and a
little bit of processing to make the traces easier to use.

Timing is provided one of three ways:

+ Lua - with a debug hook calling `os.clock`
+ LuaJIT - with a debug hook calling `ffi.C.clock` - `os.clock` is not yet implemented as a fast function
+ Lua - if c_hook has been built then that's used instead of the Lua hook.
  The hook should be able to call `clock` closer to actual code execution, so the traces should be more accurate.

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

+ Times probably aren't accurate because of the time spent getting between user code and the hooks
+ The profile back end seems to get numbers wrong - it told me a blank line took was executed several hundred times and took 0.02 of a second
+ Tail calls and coroutines will cause chaos
+ There aren't many back-ends


## 5. Alternatives

See [the Lua Wiki](http://lua-users.org/wiki/ProfilingLuaCode) for a list of profiling alternatives.
[luacov](http://luacov.luaforge.net/) provides coverage analysis.


