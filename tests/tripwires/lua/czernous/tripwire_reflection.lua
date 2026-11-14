-- Violation: builds code at runtime.
local f = loadstring('return 1')
return { f = f }
