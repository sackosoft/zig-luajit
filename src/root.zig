const std = @import("std");
const testing = std.testing;

const c = @import("c");

const OutOfMemory = error{OutOfMemory};

const allocator_adapter = @import("allocator_adapter.zig").alloc;
const types = @import("types.zig");
const LuaType = types.LuaType;

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

    /// Returns the type of the value in the given acceptable index, or LUA_TNONE for a non-valid index
    /// (that is, an index to an "empty" stack position). The types returned are coded by constants:
    /// LUA_TNIL, LUA_TNUMBER, LUA_TBOOLEAN, LUA_TSTRING, LUA_TTABLE, LUA_TFUNCTION,
    /// LUA_TUSERDATA, LUA_TTHREAD, and LUA_TLIGHTUSERDATA.
    ///
    /// Note: This function was renamed from `type` due to naming conflicts with Zig's `type` keyword.
    ///
    /// From: int lua_type(lua_State *L, int index);
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_type
    /// Stack Behavior: [-0, +0, -]
    pub fn typeOf(lua: *Lua, index: i32) LuaType {
        const t = c.lua_type(@ptrCast(lua), @as(c_int, @intCast(index)));
        return std.meta.intToEnum(LuaType, t) catch unreachable;
    }

    /// Returns true if the value at the given acceptable index has type boolean, false otherwise.
    ///
    /// From: int lua_isboolean(lua_State *L, int index);
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_isboolean
    /// Stack Behavior: [-0, +0, -]
    pub fn isBoolean(lua: *Lua, index: i32) bool {
        _ = lua;
        _ = index;
        return false;
    }

    /// Returns true if the value at the given acceptable index is a C function, false otherwise.
    ///
    /// From: int lua_iscfunction(lua_State *L, int index);
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_iscfunction
    /// Stack Behavior: [-0, +0, -]
    pub fn isCFunction(lua: *Lua, index: i32) bool {
        _ = lua;
        _ = index;
        return false;
    }

    /// Returns true if the value at the given acceptable index is a function (either C or Lua), and false otherwise.
    ///
    /// From: int lua_isfunction(lua_State *L, int index);
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_isfunction
    /// Stack Behavior: [-0, +0, -]
    pub fn isFunction(lua: *Lua, index: i32) bool {
        _ = lua;
        _ = index;
        return false;
    }

    /// Returns true if the value at the given acceptable index is a light userdata, false otherwise.
    ///
    /// From: int lua_islightuserdata(lua_State *L, int index);
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_islightuserdata
    /// Stack Behavior: [-0, +0, -]
    pub fn isLightUserdata(lua: *Lua, index: i32) bool {
        _ = lua;
        _ = index;
        return false;
    }

    /// Returns true if the value at the given acceptable index is nil, and false otherwise.
    ///
    /// From: int lua_isnil(lua_State *L, int index);
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_isnil
    /// Stack Behavior: [-0, +0, -]
    pub fn isNil(lua: *Lua, index: i32) bool {
        _ = lua;
        _ = index;
        return false;
    }

    /// Returns true if the given acceptable index is not valid (that is, it refers to an element outside the current stack)
    /// or if the value at this index is nil, and false otherwise.
    ///
    /// From: int lua_isnoneornil(lua_State *L, int index);
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_isnoneornil
    /// Stack Behavior: [-0, +0, -]
    pub fn isNoneOrNil(lua: *Lua, index: i32) bool {
        _ = lua;
        _ = index;
        return false;
    }

    /// Returns true if the given acceptable index is not valid (that is, it refers to an element outside the current stack),
    /// and false otherwise.
    ///
    /// From: int lua_isnone(lua_State *L, int index);
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_isnone
    /// Stack Behavior: [-0, +0, -]
    pub fn isNone(lua: *Lua, index: i32) bool {
        _ = lua;
        _ = index;
        return false;
    }

    /// Returns true if the value at the given acceptable index is a number or a string convertible to a number,
    /// false otherwise.
    ///
    /// From: int lua_isnumber(lua_State *L, int index);
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_isnumber
    /// Stack Behavior: [-0, +0, -]
    pub fn isNumber(lua: *Lua, index: i32) bool {
        _ = lua;
        _ = index;
        return false;
    }

    /// Returns true if the value at the given acceptable index is a string or a number
    /// (which is always convertible to a string), and false otherwise.
    ///
    /// From: int lua_isstring(lua_State *L, int index);
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_isstring
    /// Stack Behavior: [-0, +0, -]
    pub fn isString(lua: *Lua, index: i32) bool {
        _ = lua;
        _ = index;
        return false;
    }

    /// Returns true if the value at the given acceptable index is a table, false otherwise.
    ///
    /// From: int lua_istable(lua_State *L, int index);
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_istable
    /// Stack Behavior: [-0, +0, -]
    pub fn isTable(lua: *Lua, index: i32) bool {
        _ = lua;
        _ = index;
        return false;
    }

    /// Returns true if the value at the given acceptable index is a thread, and false otherwise.
    ///
    /// From: int lua_isthread(lua_State *L, int index);
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_isthread
    /// Stack Behavior: [-0, +0, -]
    pub fn isThread(lua: *Lua, index: i32) bool {
        _ = lua;
        _ = index;
        return false;
    }

    /// Returns true if the value at the given acceptable index is a userdata
    /// (either full or light), and false otherwise.
    ///
    /// From: int lua_isuserdata(lua_State *L, int index);
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_isuserdata
    /// Stack Behavior: [-0, +0, -]
    pub fn isUserdata(lua: *Lua, index: i32) bool {
        _ = lua;
        _ = index;
        return false;
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
