local trace_file = require("luatrace.trace_file")

local source_files                              -- Map of source files we've seen
local functions                                 -- Map of functions
local lines                                     -- Map of lines

local threads                                   -- All the running threads
local thread_stack                              -- and the order they're running in

local stack                                     -- Call stack

local total_time                                -- Running total of all the time we've recorded

local trace_count                               -- How many traces we've seen (for reporting errors)
local error_count                               -- How many errors we've seen

local profile = {}


--------------------------------------------------------------------------------

function profile.open()
  source_files, functions, lines = {}, {}, {}
  local main_thread = { top=0 }
  threads = { main_thread }
  thread_stack = { main_thread, top=1 }
  stack = { top=0 }
  total_time = 0
  trace_count, error_count = 0, 0
end


-- Recording -------------------------------------------------------------------

local function get_source_file(filename)
  local source_file = source_files[filename]
  if not source_file then
    source_file = { filename=filename, lines = {} }
    source_files[filename] = source_file
  end
  return source_file
end


local function get_function(filename, line_defined, last_line_defined)
  local name = filename..":"..tostring(line_defined).."-"..tostring(last_line_defined)
  local f = functions[name]
  if not f then
    f = { name=name, source_file=get_source_file(filename), line_defined=line_defined, last_line_defined=last_line_defined }
    functions[name] = f
  end
  return f
end


local function get_thread(thread_id)
  local thread = threads[thread_id]
  if not thread then
    thread = { top=0 }
    threads[thread_id] = thread
  end
  return thread
end


local function replay_push(frame)
  stack.top = stack.top + 1
  stack[stack.top] = frame
end


local function push(frame)
  replay_push(frame)
  local thread = thread_stack[thread_stack.top]
  thread.top = thread.top + 1
  thread[thread.top] = { func=frame.func }
end


local function push_thread(thread)
  thread_stack.top = thread_stack.top + 1
  thread_stack[thread_stack.top] = thread
end


local function get_top()
  return stack[stack.top]
end


local function thread_top()
  return thread_stack[thread_stack.top]
end


local function pop_thread()
  local thread = thread_stack[thread_stack.top]
  thread_stack[thread_stack.top] = nil
  thread_stack.top = thread_stack.top - 1
  return thread
end


local function replay_pop()
  local frame = stack[stack.top]
  stack[stack.top] = nil
  stack.top = stack.top - 1
  return frame
end


local function pop()
  local frame = replay_pop()
  local thread = thread_top()
  if thread.top == 0 then
    pop_thread()
    thread = thread_top()
  end
  if thread then
    thread[thread.top] = nil
    thread.top = thread.top - 1
  end
  return frame
end


local function get_line(line_number)
  local top = get_top()
  local line = top.source_file.lines[line_number]
  if not line then
    line = { file=top.source_file, line_number=line_number, visits=0, self_time=0, child_time=0 }
    top.source_file.lines[line_number] = line
    lines[#lines+1] = line
  end
  return line
end


local function clear_frame_time(caller, time, callee_source_file, callee_line_number, offset)
  -- Counting frame time for recursive functions is tricky.
  -- We have to crawl up the stack, and if we find the function or line that
  -- generated the frame time running higher up the stack, we have to subtract
  -- the callee time from the higher function's child time (because we're going
  -- to add the same time to the higher copy of the function later and we don't
  -- want to add it twice)
--  caller.frame_time = caller.frame_time + time

  for j = stack.top - offset, 1, -1 do
    local framej = stack[j]
    if framej.source_file == callee_source_file and framej.func.line_defined == callee_line_number then
      local current_line = framej.source_file.lines[framej.current_line]
      current_line.child_time = current_line.child_time - time
      break
    end
  end
end


local function play_return(callee, caller)
  local current_line = caller.source_file.lines[caller.current_line]
  current_line.child_time = current_line.child_time + callee.frame_time

  caller.frame_time = caller.frame_time + callee.frame_time
  clear_frame_time(caller, callee.frame_time, callee.source_file, callee.func.line_defined, 0)
  clear_frame_time(caller, callee.frame_time, caller.source_file, caller.current_line, 1)
end


function profile.record(a, b, c, d)
  trace_count = trace_count + 1

  if a == "S" or a == ">" then                  -- Call or start
    local filename, line_defined, last_line_defined = b, c, d
    local source_file = get_source_file(filename)
    local func = get_function(filename, line_defined, last_line_defined)
    push{ source_file=source_file, func=func, frame_time=0 }

  elseif a == "<" then                          -- Return
    if stack.top <= 0 then
      error_count = error_count + 1
      local top = get_top()
      io.stderr:write(("ERROR (%4d, line %7d): tried to return above end of stack from function defined at %s:%d-%d\n"):
        format(error_count, trace_count, top.source_file.filename, top.line_defined or 0, top.last_line_defined or 0))
    else
      local callee = pop()
      local caller = get_top()
      if caller then
        caller.protected = false
        play_return(callee, caller)
      end
    end

  elseif a == "R" then                         -- Resume
    local thread_id = b
    local thread = get_thread(thread_id)
    -- replay the thread onto the stack
    for _, frame in ipairs(thread) do
      replay_push{ source_file=frame.func.source_file, func=frame.func, frame_time=0, current_line=frame.current_line }
    end
    push_thread(thread)

  elseif a == "Y" then                         -- Yield
    if thread_stack.top <= 0 then
      error_count = error_count + 1
      local top = get_top()
      io.stderr:write(("ERROR (%4d, line %7d): tried to yield to unknown thread from function defined at %s:%d-%d\n"):
        format(error_count, trace_count, top.source_file.filename, top.line_defined or 0, top.last_line_defined or 0))
    else
      local thread = thread_top()
      -- unwind the thread from the stack
      for i = thread.top, 1, -1 do
        local callee = replay_pop()
        local caller = get_top()
        thread[i].current_line = callee.current_line
        play_return(callee, caller)
      end
      pop_thread()
    end

  elseif a == "P" then                         -- pcall
    get_top().protected = true

  elseif a == "E" then                         -- Error!
    while true do
      local callee = pop()
      local caller = get_top()
      if not caller then break end
      play_return(callee, caller)
      if caller.protected then
        caller.protected = false
        break
      end
    end

  else                                         -- Line
    local line_number, time = a, b
    total_time = total_time + time

    local top = get_top()

    if top.func.line_defined > 0 and
      (line_number < top.func.line_defined or line_number > top.func.last_line_defined) then
      error_count = error_count + 1
      io.stderr:write(("ERROR (%4d, line %7d): counted execution of %d microseconds at line %d of a function defined at %s:%d-%d\n"):
        format(error_count, trace_count, time, line_number, top.source_file.filename, top.func.line_defined, top.func.last_line_defined))
    end

    local line = get_line(line_number)
    if top.current_line ~= line_number then
      line.visits = line.visits + 1
    end
    line.self_time = line.self_time + time
    top.frame_time = top.frame_time + time
    clear_frame_time(top, time, top.source_file, line_number, 1)
    top.current_line = line_number
  end
end


-- Generating reports ----------------------------------------------------------

function profile.close()
  local all_lines = {}

  -- Work out the "most" of some numbers, so we can format reports better
  local max_time, max_visits, max_line_number = 0, 0, 0
  for _, l in ipairs(lines) do
    max_time = math.max(max_time, l.self_time + l.child_time)
    max_visits = math.max(max_visits, l.visits)
    max_line_number = math.max(max_line_number, l.line_number)
  end

  local divisor, time_units, time_format
  if max_time < 10 then
    divisor = 0.001
    time_units = "nanoseconds"
    time_format = "d"
  elseif max_time < 10000 then
    divisor = 1
    time_units = "microseconds"
    time_format = ".2f"
  elseif max_time < 10000000 then
    divisor = 1000
    time_units = "milliseconds"
    time_format = ".2f"
  else
    divisor = 1000000
    time_units = "seconds"
    time_format = ".2f"
  end
  local function number_format(title, fmt, max_value)
    local f1 = "%"..fmt
    local max_len = f1:format(max_value):len()
    max_len = math.max(title:len(), max_len)
    local number_format = ("%%%d"..fmt):format(max_len)
    local string_format = ("%%%ds"):format(max_len)
    return number_format, string_format
  end

  local time_nformat, time_sformat = number_format("Child", time_format, max_time / divisor)
  local visit_nformat, visit_sformat = number_format("Visits", "d", max_visits)
  local line_number_nformat, line_number_sformat = number_format("line", "d", max_line_number)

  -- Read all the source files, and sort them into alphabetical order
  local max_line_length = 0
  local sorted_source_files = {}
  for _, f in pairs(source_files) do
    if not f.filename:match("luatrace") then
      local s = io.open(f.filename, "r")
      if s then
        sorted_source_files[#sorted_source_files+1] = f
        local i = 1
        for l in s:lines() do
          max_line_length = math.max(max_line_length, l:len())
          if f.lines[i] then
            f.lines[i].text = l
          else
            f.lines[i] = { text=l, file=f, line_number=i }
          end
          i = i + 1
        end
      end
      s:close()
    end
  end
  table.sort(sorted_source_files, function(a, b) return a.filename < b.filename end)

  -- Write annotated source
  local header_format = visit_sformat.." "..time_sformat.." "..time_sformat.." "..time_sformat.." "..line_number_sformat.." | "
  local header = header_format:format("Visits", "Total", "Self", "Child", "Line")
  local line_format = visit_nformat.." "..time_nformat.." "..time_nformat.." "..time_nformat.." "..line_number_nformat.." | %s\n"
  local asf = io.open("annotated-source.txt", "w")
  for _, f in ipairs(sorted_source_files) do
    asf:write(("="):rep(header:len() + max_line_length), "\n")
    asf:write(header, f.filename, " - Times in ", time_units, "\n")
    asf:write(("-"):rep(header:len() + max_line_length), "\n")
    for i, l in ipairs(f.lines) do
      if l.visits then
        asf:write(line_format:format(l.visits, (l.self_time+l.child_time) / divisor, l.self_time / divisor, l.child_time / divisor, i, l.text))
      else
        asf:write(header_format:format(".", ".", ".", ".", tonumber(l.line_number)), l.text, "\n")
      end
    end
    asf:write("\n")
  end
  asf:close()

  -- Report on the lines using the most time
  table.sort(lines, function(a, b) return a.self_time + a.child_time > b.self_time + b.child_time end)

  local title_len = 9
  for i = 1, math.min(20, #lines) do
    local l = lines[i]
    l.title = ("%s:%d"):format(l.file.filename, l.line_number)
    title_len = math.max(title_len, l.title:len())
  end
  local title_format = ("%%-%ds"):format(title_len)

  io.stderr:write(("Total time "..time_nformat.." %s\n"):format(total_time / divisor, time_units))
  io.stderr:write("Times in ", time_units, "\n")

  header_format = title_format.."  "..visit_sformat.."  "..time_sformat.."  "..time_sformat.."  "..time_sformat.. " | Line\n"
  io.stderr:write(header_format:format("File:line", "Visits", "Total", "Self", "Child"))
  line_format = title_format.."  "..visit_nformat.."  "..time_nformat.."  "..time_nformat.."  "..time_nformat.. " | %s\n"

  for i = 1, math.min(20, #lines) do
    local l = lines[i]
    io.stderr:write(line_format:format(l.title, l.visits,
      (l.self_time + l.child_time) / divisor, l.self_time/divisor, l.child_time/divisor,
      l.text or "-"))
  end
end


-- Stopping and starting -------------------------------------------------------

function profile.go()
  trace_file.read{ recorder=profile }
end


local luatrace = require("luatrace")

function profile.tron(settings)
  settings = settings or {}
  settings.recorder = profile
  return luatrace.tron(settings)
end

profile.troff = luatrace.troff


-- Main ------------------------------------------------------------------------

if arg and type(arg) == "table" and string.match(debug.getinfo(1, "S").short_src, arg[0]) then
  profile.go()
end


--------------------------------------------------------------------------------

return profile


-- EOF -------------------------------------------------------------------------

