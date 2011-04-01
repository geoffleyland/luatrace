local DEFAULT_RECORDER = "luatrace.trace_file"


-- Check if the ffi is available, and get a handle on the c library's clock.
-- LuaJIT doesn't compile traces containing os.clock yet.
local ffi
if jit and jit.status and jit.status() then
  local ok
  ok, ffi = pcall(require, "ffi")
  if ok then
    ffi.cdef("unsigned long clock(void);") 
  else
    ffi = nil
  end
end

-- See if the c hook is available
local c_hook
do
  local ok
  ok, c_hook = pcall(require, "luatrace.c_hook")
  if not ok then
    c_hook = nil
  end
end


-- Trace recording -------------------------------------------------------------

local recorder                          -- The thing that's recording traces
local current_line                      -- The line we currently think is active
local accumulated_us                    -- The microseconds we've accumulated for that line


-- Emit a trace if the current line has changed
-- and reset the current line and accumulated time
local function set_current_line(l)
  if l ~= current_line then
    -- if the current line *is* -1 then we're in a series of tail calls,
    -- and we'll throw the accumulated time away - most of it's probably
    -- trace overhead anyway
    if current_line ~= -1 then
      recorder.record(current_line, accumulated_us)
    end
    accumulated_us = 0
    current_line = l
  end
end


-- We only trace Lua functions
local function should_trace(f)
  return f and f.source:sub(1,1) == "@"
end


local CALLEE_INDEX, CALLER_INDEX

local watch_thread

-- Record an action reported to the hook.
local function record(action, line, time)
  accumulated_us = accumulated_us + time

  if watch_thread then
    if action == "call" then
      -- Whether the thread changed (and this is the *first* resume on the thread)
      -- or the thread was dead, and we're still in the same thread doesn't matter
      -- we're going to do what we want - report a call.
      watch_thread = nil
    elseif action == "line" then
      if watch_thread ~= (coroutine.running() or 1) then
        -- This was a resume into a running thread.  We make it look like a call
        local current = debug.getinfo(CALLEE_INDEX, "Sl")
        recorder.record(">", current.short_src, current.linedefined, current.lastlinedefined)
      end
      watch_thread = nil
    end
  end

  if action == "line" then
    set_current_line(line)

  elseif action == "call" or action == "return" then
    local callee = debug.getinfo(CALLEE_INDEX, "Sln")
    local caller = debug.getinfo(CALLER_INDEX, "Sl")
    
    if action == "call" then
      if should_trace(caller) then
        -- square up the caller's time to the last line executed
        set_current_line(caller.currentline)
      end
      if should_trace(callee) then
        -- start charging the callee for time, and record where we're going
        set_current_line(callee.currentline)
        recorder.record(">", callee.short_src, callee.linedefined, callee.lastlinedefined)
      elseif callee and callee.source == "=[C]" then
        if callee.name == "yield" then
          -- We don't know where we're headed yet so some time is lost (and if
          -- yield gets renamed, all bets are off)
          set_current_line(-1)
          recorder.record("<")
        else
          -- Because of coroutine.wrap, any c function could resume a different
          -- thread.  Watch the current thread and catch it if it changes.
          watch_thread = coroutine.running() or 1
        end
      end

    else -- action == "return"
      if should_trace(callee) then
        -- square up the callee's time to the last line executed
        set_current_line(callee.currentline)
      end
      if not caller                             -- final return from a coroutine
        or caller.source == "=(tail call)" then -- about to get tail-returned
        -- In both cases, there's no point recording time until we're
        -- back on our feet
        set_current_line(-1)
      elseif should_trace(caller) then
        -- The caller gets charged for time from here on
        set_current_line(caller.currentline)
      end
      if should_trace(callee) then
        recorder.record("<")
      end
    end

  elseif action == "tail return" then
    local caller = debug.getinfo(CALLER_INDEX, "Sl")
    -- If we've got a real caller, we're heading back to non-tail-call land
    -- start charging the caller for time
    if should_trace(caller) then
      set_current_line(caller.currentline)
    end
    recorder.record("<")
  end
end


-- The hooks -------------------------------------------------------------------

-- The Lua version of the hook uses os.clock
-- The LuaJIT version of the hook uses ffi.C.clock

local time_out                          -- Time we last left the hook

-- The hook - note the time and record something
local function hook_lua(action, line)
  local time_in = os.clock()
  record(action, line, (time_in - time_out) * 1000000)
  time_out = os.clock()
end
local function hook_luajit(action, line)
  local time_in = ffi.C.clock()
  record(action, line, time_in - time_out)
  time_out = ffi.C.clock()
end


-- Starting the hook - we go to unnecessary trouble to avoid reporting the
-- first few lines, which are inside and returning from luatrace.tron
local start_short_src, start_line

local function init_trace(line)
  local caller = debug.getinfo(3, "S")
  recorder.record("S", caller.short_src, caller.linedefined, caller.lastlinedefined)
  current_line, accumulated_us = line, 0
end

local function hook_lua_start(action, line)
  init_trace(line)
  CALLEE_INDEX, CALLER_INDEX = 3, 4
  debug.sethook(hook_lua, "crl")
  time_out = os.clock()
end
local function hook_luajit_start(action, line)
  init_trace(line)
  CALLEE_INDEX, CALLER_INDEX = 3 ,4
  debug.sethook(hook_luajit, "crl")
  time_out = ffi.C.clock()
end
local function hook_c_start(action, line)
  init_trace(line)
  CALLEE_INDEX, CALLER_INDEX = 2, 3
  c_hook.set_hook(record)
end


local function hook_start()
  local callee = debug.getinfo(2, "Sl")
  if callee.short_src == start_short_src and callee.linedefined == start_line then
    if ffi then
      debug.sethook(hook_luajit_start, "l")
    elseif c_hook then
      debug.sethook(hook_c_start, "l")
    else
      debug.sethook(hook_lua_start, "l")
    end
  end
end


-- Shutting down ---------------------------------------------------------------

local luatrace_exit_trick_file_name = os.tmpname()
local luatrace_raw_exit = os.exit


local function luatrace_on_exit()
  recorder.close()
  os.remove(luatrace_exit_trick_file)
end


local function luatrace_exit_trick()
  luatrace_exit_trick_file = io.open(luatrace_exit_trick_file_name, "w")
  debug.setmetatable(luatrace_exit_trick_file, { __gc = luatrace_on_exit } )
  os.exit = function(...)
    luatrace_on_exit()
    luatrace_raw_exit(...)
  end
end


-- API Functions ---------------------------------------------------------------

local luatrace = {}

-- Turn the tracer on
function luatrace.tron(settings)
  if settings and settings.recorder then
    if type(settings.recorder) == "string" then
      recorder = require(settings.recorder)
    else
      recorder = settings.recorder
    end
  end
  if not recorder then recorder = require(DEFAULT_RECORDER) end
  recorder.open(settings)

  local me = debug.getinfo(1, "Sl")
  start_short_src, start_line = me.short_src, me.linedefined

  luatrace_exit_trick()

  debug.sethook(hook_start, "r")
end


-- Turn it off and close the recorder
function luatrace.troff()
  debug.sethook()
  recorder.close()
  os.remove(luatrace_exit_trick_file_name)
  os.exit = luatrace_raw_exit
end


return luatrace

-- EOF -------------------------------------------------------------------------

