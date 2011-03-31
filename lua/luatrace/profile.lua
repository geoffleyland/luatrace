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

  io.stderr:write(("%-35s%8s%12s%12s%12s\n"):
    format("File:line", "Visits", "Total", "Self", "Children"))
  for i = 1, math.min(20, #all_lines) do
    local l = all_lines[i]
    local name = ("%s:%d"):format(l.filename, l.line_number)
    io.stderr:write(("%-35s%8d%12.6f%12.6f%12.6f\n"):format(name, l.line.visits,
      l.line.self_time/1000000 + l.line.child_time/1000000, l.line.self_time/1000000, l.line.child_time/1000000))
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

