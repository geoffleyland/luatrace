luatrace = require("luatrace")

function factorial(n, p)
  if n == 1 then return p or 1 end
  return factorial(n - 1, (p or 1) * n)
end

luatrace.tron()
print(factorial(1))
print(factorial(2))
print(factorial(3))
luatrace.troff()

