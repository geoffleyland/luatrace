luatrace = require("luatrace")

function a(i)
  print("wait a")
  if i > 1 then
    return b(i-1)
  end
end

function b(i)
  print("wait b")
  if i > 1 then
    return a(i-1)
  end
end

luatrace.tron()
a(6)
luatrace.troff()