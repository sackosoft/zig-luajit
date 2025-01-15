const std = @import("std");
const testing = std.testing;

const c = @import("c");

const OutOfMemory = error{OutOfMemory};

const allocator_adapter = @import("allocator_adapter.zig").alloc;

/// A Lua state represents the entire context of a Lua interpreter.
/// Each state is completely independent and has no global variables.
///
/// The state must be initialized with init() and cleaned up with deinit().
/// All Lua operations require a pointer to a state as their first argument,
/// except for init() which creates a new state.
///
/// From: `typedef struct lua_State lua_State;`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_State
const Lua = opaque {
    /// Creates a new Lua state with the provided allocator.
    ///
    /// The allocator is copied to the heap to ensure a stable address, as Lua requires
    /// the allocator to remain valid for the lifetime of the state. This copy is freed
    /// when deinit() is called.
    ///
    /// Caller owns the returned Lua state and must call deinit() to free resources.
    ///
    pub fn init(alloc: std.mem.Allocator) OutOfMemory!*Lua {
        // alloc could be stack-allocated by the caller, but Lua requires a stable address.
        // We will create a pinned copy of the allocator on the heap.
        const alloc_copy = try alloc.create(std.mem.Allocator);
        errdefer alloc.destroy(alloc_copy);
        alloc_copy.* = alloc;

        const lua: ?*Lua = @ptrCast(c.lua_newstate(allocator_adapter, alloc_copy));
        return if (lua) |p| p else error.OutOfMemory;
    }

    /// Closes the Lua state and frees all resources.
    ///
    /// This includes:
    /// - All memory allocated by Lua
    /// - The heap-allocated copy of the caller-provided `std.mem.Allocator` instance
    ///   that was created in init()
    ///
    /// The Lua pointer is invalid after this call.
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
