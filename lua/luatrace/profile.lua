local trace_file = require("luatrace.trace_file")

local source_files
local stack
local stack_top
local total_time
local count
local errors

local profile = {}


function profile.open()
  source_files, stack, stack_top, total_time, count, errors = {}, {}, 0, 0, 0, 0
end


function profile.record(a, b, c, d)
  count = count + 1
  if a == "S" or a == ">" then
    filename, line_defined, last_line_defined = b, c, d
    file = source_files[filename]
    if not file then
      file = { filename=filename, lines = {} }
      source_files[filename] = file
    end
    stack_top = stack_top + 1
    stack[stack_top] = { file=file, filename=filename, line_defined=line_defined, last_line_defined=last_line_defined, frame_time=0 }

  elseif a == "<" then
    if stack_top > 1 then
      local callee = stack[stack_top]
      stack[stack_top] = nil
      stack_top = stack_top - 1
      local top = stack[stack_top]
      top.file.lines[top.current_line].child_time = top.file.lines[top.current_line].child_time + callee.frame_time
      top.frame_time = top.frame_time + callee.frame_time

      -- Recursive functions are hard - we have to crawl up the stack, and if we
      -- find the function that just returned running higher up the stack,
      -- subtract the callee time from the higher function's child time (because
      -- we're going to add the same time to the higher copy of the function
      -- later and we don't want to add it twice)
      for j = stack_top, 1, -1 do
        local framej = stack[j]
        if framej.filename == callee.filename and framej.line_defined == callee.line_defined then
          framej.file.lines[framej.current_line].child_time = framej.file.lines[framej.current_line].child_time - callee.frame_time
          break
        end
      end
    end

  else
    local line, time = a, b
    total_time = total_time + time

    local top = stack[stack_top]

    if top.line_defined > 0 and
      (line < top.line_defined or line > top.last_line_defined) then
      errors = errors + 1
      io.stderr:write(("ERROR (%4d, line %7d): counted execution of %d microseconds at line %d of a function defined at %s:%d-%d\n"):
        format(errors, count, time, line, top.file.filename, top.line_defined, top.last_line_defined))
    end

    local r = top.file.lines[line]
    if not r then
      r = { visits = 0, self_time = 0, child_time = 0 }
      top.file.lines[line] = r
    end
    if top.current_line ~= line then
      r.visits = r.visits + 1
    end
    r.self_time = r.self_time + time
    top.frame_time = top.frame_time + time
    top.current_line = line
  end
end


function profile.close()
  local all_lines = {}

  -- collect all the lines
  local max_visits = 0
  for _, f in pairs(source_files) do
    for i, l in pairs(f.lines) do
      all_lines[#all_lines + 1] = { filename=f.filename, line_number=i, line=l }
      max_visits = math.max(max_visits, l.visits)
    end
  end
  table.sort(all_lines, function(a, b) return a.line.self_time + a.line.child_time > b.line.self_time + b.line.child_time end)
  local max_time = all_lines[1].line.self_time + all_lines[1].line.child_time
  
  local divisor, time_units
  if max_time < 10000 then
    divisor = 1
    time_units = "microseconds"
  elseif max_time < 10000000 then
    divisor = 1000
    time_units = "milliseconds"
  else
    io.stderr:write("Times in seconds\n")
    divisor = 1000000
    time_units = "seconds"
  end
  

  -- Write annotated source
  local visit_format = ("%%%dd"):format(("%d"):format(max_visits):len())
  local line_format = " "..visit_format.."%12.2f%12.2f%12.2f%5d | %-s\n"
  local asf = io.open("annotated-source.txt", "w")
  for _, f in pairs(source_files) do
    local s = io.open(f.filename, "r")
    if s then
      asf:write("\n")
      asf:write("====================================================================================================\n")
      asf:write(f.filename, "  ", "Times in ", time_units, "\n\n")
      local i = 1
      for l in s:lines() do
        local rec = f.lines[i]
        if rec then
          asf:write(line_format:format(rec.visits, (rec.self_time+rec.child_time) / divisor, rec.self_time / divisor, rec.child_time / divisor, i, l))
        else
          asf:write(line_format:format(0, 0, 0, 0, i, l))
        end
        i = i + 1
      end
    end
    s:close()
  end
  asf:close()

  local title_len = 0
  local file_lines = {}
  for i = 1, math.min(20, #all_lines) do
    local l = all_lines[i]

    l.title = ("%s:%d"):format(l.filename, l.line_number)
    title_len = math.max(title_len, l.title:len())
    
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
    local f = io.open(file_name, "r")
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

  io.stderr:write("Times in ", time_units, "\n")
  io.stderr:write(("Total time %.2f\n"):format(total_time / divisor))

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

