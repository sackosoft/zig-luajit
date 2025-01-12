const std = @import("std");
const testing = std.testing;

const c = @import("c");

test "Lua JIT is avialable" {
    _ = c.luaL_newstate() orelse unreachable;
    _ = c.lua_State;

    try testing.expect(1 == 1);
    std.debug.print("Running test\n", .{});
}
