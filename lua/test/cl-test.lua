-- run me with 'lua -luatrace cl-test.lua'

function b()
  return 1
end
function c()
  return 2
end

local a = b() + c()
print(a + b())
