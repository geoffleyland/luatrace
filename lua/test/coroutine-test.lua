luatrace = require("luatrace")

function co()
  for i = 1, 3 do
    coroutine.yield(i)
  end
end


function test_resume(t)
  while true do
    local status, i = coroutine.resume(t)
    if not status then print("ERROR: ", i) break end
    if not i then break end
  end
end


function test_wrap(f)
  while true do
    local i = f()
    if not i then break end
  end
end


luatrace.tron()
test_resume(coroutine.create(co))
test_wrap(coroutine.wrap(co))
luatrace.troff()