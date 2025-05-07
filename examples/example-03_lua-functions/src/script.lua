-- Declare a function to be called from Zig
function operator(x, y)
	print("[Lua] Running `operator` function")
	print("[Lua] Got two arguments: " .. x .. ", " .. y)
	print("[Lua] Multiplying numbers")
	return x * y
end
