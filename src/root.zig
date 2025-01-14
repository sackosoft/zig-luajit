const std = @import("std");
const testing = std.testing;

const c = @import("c");

const OutOfMemory = error{OutOfMemory};

const allocator_adapter = @import("allocator_adapter.zig").alloc;
const Lua = opaque {
    pub fn init(alloc: std.mem.Allocator) OutOfMemory!*Lua {
        // alloc could be stack-allocated by the caller, but Lua requires a stable address.
        // We will create a pinned copy of the allocator on the heap.
        const alloc_copy = try alloc.create(std.mem.Allocator);
        errdefer alloc.destroy(alloc_copy);
        alloc_copy.* = alloc;

        return c.lua_newstate(allocator_adapter, alloc_copy) orelse error.OutOfMemory;
    }

    pub fn deinit(lua: *Lua) void {
        var alloc_copy: ?*std.mem.Allocator = undefined;
        _ = c.lua_getallocf(@ptrCast(lua), @ptrCast(&alloc_copy)).?;

        c.lua_close(@ptrCast(lua));

        if (alloc_copy) |alloc| {
            alloc.destroy(alloc);
        }
    }
};

test "Lua JIT is avialable" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    const lua = try Lua.init(alloc);
    defer lua.deinit();

    std.debug.print("Running test\n", .{});
}
