local trace_file = require("luatrace.trace_file")

local source_files
local stack
local stack_top

local profile = {}


function profile.open()
  source_files, stack, stack_top = {}, {}, 0
end


local function call(filename, line)
  line = tonumber(line)
  file = source_files[filename]
  if not file then
    file = { name = filename, lines = {} }
    source_files[filename] = file
  end
  stack_top = stack_top + 1
  stack[stack_top] = { file=file, defined_line = line, total_time = 0 }
end


function profile.record(a, b, c)
  if a == "S" or a == ">" then
    filename, line = b, c
    file = source_files[filename]
    if not file then
      file = { name = filename, lines = {} }
      source_files[filename] = file
    end
    stack_top = stack_top + 1
    stack[stack_top] = { file=file, defined_line = line, total_time = 0 }

  elseif a == "<" then
    if stack_top > 1 then
      local total_time = stack[stack_top].total_time
      stack[stack_top] = nil
      stack_top = stack_top - 1
      local top = stack[stack_top]
      top.file.lines[top.current_line].child_time = top.file.lines[top.current_line].child_time + total_time
      top.total_time = top.total_time + total_time
    end

  else
    local line, time = a, b
    line, time = tonumber(line), tonumber(time)
    local top = stack[stack_top]
    local r = top.file.lines[line]
    if not r then
      r = { visits = 0, self_time = 0, child_time = 0 }
      top.file.lines[line] = r
    end
    if top.current_line ~= line then
      r.visits = r.visits + 1
    end
    r.self_time = r.self_time + time
    top.total_time = top.total_time + time
    top.current_line = line
  end
end


function profile.close()
  local all_lines = {}

  for _, f in pairs(source_files) do
    for i, l in pairs(f.lines) do
      all_lines[#all_lines + 1] = { filename=f.name, line_number=i, line=l }
    end
  end

  table.sort(all_lines, function(a, b) return a.line.self_time + a.line.child_time > b.line.self_time + b.line.child_time end)


  local title_len, max_time = 0, 0
  local file_lines = {}
  for i = 1, math.min(20, #all_lines) do
    local l = all_lines[i]

    l.title = ("%s:%d"):format(l.filename, l.line_number)
    title_len = math.max(title_len, l.title:len())
    
    max_time = math.max(max_time, l.line.self_time + l.line.child_time)

    -- Record the lines of the files we want to see
    local fl = file_lines[l.filename]
    if not fl then
      fl = {}
      file_lines[l.filename] = fl
    end
    fl[l.line_number] = i
  end

  -- Find the text of the lines
  for file_name, line_numbers in pairs(file_lines) do
    local f = assert(io.open(file_name, "r"))
    if f then
      local i = 1
      for l in f:lines() do
        local j = line_numbers[i]
        if j then
          all_lines[j].line_text = l
        end
        i = i + 1
      end
    end
    f:close()
  end

  local divisor
  if max_time < 10000 then
    io.stderr:write("Times in microseconds\n")
    divisor = 1
  elseif max_time < 10000000 then
    io.stderr:write("Times in milliseconds\n")
    divisor = 1000
  else
    io.stderr:write("Times in seconds\n")
    divisor = 1000000
  end

  header_format = ("%%-%ds%%8s%%12s%%12s%%12s  Line\n"):format(title_len+2)
  line_format = ("%%-%ds%%8d%%12.2f%%12.2f%%12.2f  %%-s\n"):format(title_len+2)
  io.stderr:write(header_format:format("File:line", "Visits", "Total", "Self", "Children"))

  for i = 1, math.min(20, #all_lines) do
    local l = all_lines[i]
    io.stderr:write(line_format:format(l.title, l.line.visits,
      (l.line.self_time + l.line.child_time) / divisor, l.line.self_time/divisor, l.line.child_time/divisor,
      l.line_text or "-"))
  end
end


function profile.go()
  trace_file.read{ recorder=profile }
end


-- Main ------------------------------------------------------------------------

if arg and type(arg) == "table" and string.match(debug.getinfo(1, "S").short_src, arg[0]) then
  profile.go()
end


--------------------------------------------------------------------------------

return profile


-- EOF -------------------------------------------------------------------------

