-- Detecting coroutine resumes and traces is tricky, particularly as
-- + thanks to coroutine.wrap, you might resume from any function
-- + if the thread is finished, resume doesn't cause a thread change
-- + threads finish by returning, without a call to yield
-- Here we only test yielding from the top of the thread stack

luatrace = require("luatrace")

function ok()
  return 1
end


function pcall_ok()
  local status, i = pcall(ok)
end


luatrace.tron()
pcall_ok()
luatrace.troff()