-- Write luatrace traces to a file. Each line is one of
-- S <filename> <linedefined>           -- Start a trace at filename somewhere in the function defined at linedefined
-- <linenumber> <microseconds>          -- Accumulate microseconds against linenumber
-- > <filename> <linedefined>           -- Call into the function defined at linedefined of filename
-- <                                    -- Return from a function
-- Usually, a line will have time accumulated to it before and after it calls a function, so
-- function b() return 1 end
-- function c() return 2 end
-- a = b() + c()
-- will be traced as
-- 3 (time)
-- > (file) 1
-- 1 (time)
-- <
-- 3 (time)
-- > (file) 2
-- 2 (time)
-- <
-- 3 (time)


local DEFAULT_TRACE_LIMIT = 10000       -- How many traces to store before writing them out
local DEFAULT_TRACE_FILE_NAME = "trace-out.txt"
                                        -- What to call the trace file

-- Maybe these should be fields of a trace-file table.
local traces                            -- Array of traces
local count                             -- Number of traces
local limit                             -- How many traces we'll hold before we write them to...
local file                              -- The file to write traces to


-- Write traces to a file ------------------------------------------------------

local function write_trace(a, b, c)
  if a == ">" or a == "S" then
    file:write(a, " ", tostring(b), " ", tostring(c), "\n")
  elseif a == "<" then
    file:write("<\n")
  else
    file:write(tonumber(a), " ", ("%d"):format(tonumber(b)), "\n")
  end
end


local function write_traces()
  for i = 1, count do
    local t = traces[i]
    write_trace(t[1], t[2], t[3])
  end
  count = 0
end


-- API -------------------------------------------------------------------------

local trace_file = {}

function trace_file.record(a, b, c)
  if limit < 2 then
    write_trace(a, b, c)
  else
    count = count + 1
    traces[count] = { a, b, c }
    if count > limit then write_traces() end
  end
end


function trace_file.open(settings)
  if settings and settings.trace_file then
    file = settings.trace_file
  elseif settings and settings.trace_file_name then
    file = assert(io.open(trace_file_name, "w"), "Couldn't open trace file")
  else
    file = assert(io.open(DEFAULT_TRACE_FILE_NAME, "w"), "Couldn't open trace file")
  end

  limit = (settings and settings.trace_limit) or DEFAULT_TRACE_LIMIT

  count, traces = 0, {}
end


function trace_file.close()
  if file then
    write_traces()
    file:close()
    file = nil
  end
end


function trace_file.read(settings)
  local do_not_close_file
  if settings and settings.trace_file then
    file = settings.trace_file
    do_not_close_file = true
  elseif settings and settings.trace_file_name then
    file = assert(io.open(trace_file_name, "r"), "Couldn't open trace file")
  else
    file = assert(io.open(DEFAULT_TRACE_FILE_NAME, "r"), "Couldn't open trace file")
  end

  local recorder = settings.recorder

  recorder.open(settings)
  for l in file:lines() do
    local l1 = l:sub(1, 1)
    if l1 == "S" or l1 == ">" then
      local filename, line = l:match("..(%S+) (%d+)")
      recorder.record(l1, filename, tonumber(line))
    elseif l1 == "<" then
      recorder.record("<")
    else
      local line, time = l:match("(%d+) (%d+)")
      recorder.record(tonumber(line), tonumber(time))
    end
  end
  recorder.close()
  if not do_not_close_file then
    file:close()
  end
end


return trace_file


-- EOF -------------------------------------------------------------------------

