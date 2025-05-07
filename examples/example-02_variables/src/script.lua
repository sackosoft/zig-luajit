-- `foo` was not set in this script. It will be provided by Zig
print("[Lua] Got value of foo in Lua: " .. foo)

bar = 42 -- Set `bar` in the Lua script
print("[Lua] Set bar to: " .. bar)
