const std = @import("std");
const testing = std.testing;

const c = @import("c");
fn asState(lua: *Lua) *c.lua_State {
    return @ptrCast(lua);
}

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
    pub const Number = c.LUA_NUMBER;
    pub const Integer = c.LUA_INTEGER;
    pub const Type = enum(i5) {
        None = c.LUA_TNONE,
        Nil = c.LUA_TNIL,
        Boolean = c.LUA_TBOOLEAN,
        Light_userdata = c.LUA_TLIGHTUSERDATA,
        Number = c.LUA_TNUMBER,
        String = c.LUA_TSTRING,
        Table = c.LUA_TTABLE,
        Function = c.LUA_TFUNCTION,
        Userdata = c.LUA_TUSERDATA,
        Thread = c.LUA_TTHREAD,
    };

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

    /// Returns the name of the type encoded by the value tp, which must be one the values returned by luaType().
    /// Caller *does not* own the returned slice.
    ///
    /// From: const char *lua_typename(lua_State *L, int tp);
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_typename
    /// Stack Behavior: [-0, +0, -]
    pub fn typeName(lua: *Lua, t: Lua.Type) [:0]const u8 {
        _ = lua;

        const type_to_name: [12][:0]const u8 = .{
            "no value",
            "nil",
            "boolean",
            "userdata",
            "number",
            "string",
            "table",
            "function",
            "userdata",
            "thread",
            "proto",
            "cdata",
        };
        const index = @intFromEnum(t) + 1;
        std.debug.assert(index >= 0);
        return type_to_name[@as(usize, @intCast(index))];
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
    pub fn typeOf(lua: *Lua, index: i32) Lua.Type {
        const t = c.lua_type(asState(lua), index);
        return @enumFromInt(t);
    }

    /// Returns true if the value at the given acceptable index is nil, and false otherwise.
    ///
    /// From: int lua_isnil(lua_State *L, int index);
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_isnil
    /// Stack Behavior: [-0, +0, -]
    pub fn isNil(lua: *Lua, index: i32) bool {
        return lua.typeOf(index) == Lua.Type.Nil;
    }

    /// Returns true if the given acceptable index is not valid (that is, it refers to an element outside the current stack)
    /// or if the value at this index is nil, and false otherwise.
    ///
    /// From: int lua_isnoneornil(lua_State *L, int index);
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_isnoneornil
    /// Stack Behavior: [-0, +0, -]
    pub fn isNoneOrNil(lua: *Lua, index: i32) bool {
        return lua.typeOf(index) == Lua.Type.None or lua.typeOf(index) == Lua.Type.Nil;
    }

    /// Returns true if the given acceptable index is not valid (that is, it refers to an element outside the current stack),
    /// and false otherwise.
    ///
    /// From: int lua_isnone(lua_State *L, int index);
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_isnone
    /// Stack Behavior: [-0, +0, -]
    pub fn isNone(lua: *Lua, index: i32) bool {
        return lua.typeOf(index) == Lua.Type.None;
    }

    /// Returns true if the value at the given acceptable index has type boolean, false otherwise.
    ///
    /// From: int lua_isboolean(lua_State *L, int index);
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_isboolean
    /// Stack Behavior: [-0, +0, -]
    pub fn isBoolean(lua: *Lua, index: i32) bool {
        return lua.typeOf(index) == Lua.Type.Boolean;
    }

    /// Returns true if the value at the given acceptable index is a function (either C or Lua), and false otherwise.
    ///
    /// From: int lua_isfunction(lua_State *L, int index);
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_isfunction
    /// Stack Behavior: [-0, +0, -]
    pub fn isFunction(lua: *Lua, index: i32) bool {
        return lua.typeOf(index) == Lua.Type.Function;
    }

    /// Returns true if the value at the given acceptable index is a light userdata, false otherwise.
    ///
    /// From: int lua_islightuserdata(lua_State *L, int index);
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_islightuserdata
    /// Stack Behavior: [-0, +0, -]
    pub fn isLightUserdata(lua: *Lua, index: i32) bool {
        return lua.typeOf(index) == Lua.Type.Light_userdata;
    }

    /// Returns true if the value at the given acceptable index is a table, false otherwise.
    ///
    /// From: int lua_istable(lua_State *L, int index);
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_istable
    /// Stack Behavior: [-0, +0, -]
    pub fn isTable(lua: *Lua, index: i32) bool {
        return lua.typeOf(index) == Lua.Type.Table;
    }

    /// Returns true if the value at the given acceptable index is a thread, and false otherwise.
    ///
    /// From: int lua_isthread(lua_State *L, int index);
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_isthread
    /// Stack Behavior: [-0, +0, -]
    pub fn isThread(lua: *Lua, index: i32) bool {
        return lua.typeOf(index) == Lua.Type.Thread;
    }

    /// Returns true if the value at the given acceptable index is a number or a string convertible to a number,
    /// false otherwise.
    ///
    /// From: int lua_isnumber(lua_State *L, int index);
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_isnumber
    /// Stack Behavior: [-0, +0, -]
    pub fn isNumber(lua: *Lua, index: i32) bool {
        return 1 == c.lua_isnumber(asState(lua), index);
    }

    /// Returns true if the value at the given acceptable index is a string or a number
    /// (which is always convertible to a string), and false otherwise.
    ///
    /// From: int lua_isstring(lua_State *L, int index);
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_isstring
    /// Stack Behavior: [-0, +0, -]
    pub fn isString(lua: *Lua, index: i32) bool {
        return 1 == c.lua_isstring(asState(lua), index);
    }

    /// Returns true if the value at the given acceptable index is a C function, false otherwise.
    ///
    /// From: int lua_iscfunction(lua_State *L, int index);
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_iscfunction
    /// Stack Behavior: [-0, +0, -]
    pub fn isCFunction(lua: *Lua, index: i32) bool {
        return 1 == c.lua_iscfunction(asState(lua), index);
    }

    /// Returns true if the value at the given acceptable index is a userdata
    /// (either full or light), and false otherwise.
    ///
    /// From: int lua_isuserdata(lua_State *L, int index);
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_isuserdata
    /// Stack Behavior: [-0, +0, -]
    pub fn isUserdata(lua: *Lua, index: i32) bool {
        return 1 == c.lua_isuserdata(asState(lua), index);
    }

    /// Pushes a nil value onto the stack.
    ///
    /// From: void lua_pushnil(lua_State *L);
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_pushnil
    /// Stack Behavior: [-0, +1, -]
    pub fn pushNil(lua: *Lua) void {
        c.lua_pushnil(asState(lua));
    }

    /// Pushes a boolean value with the given value onto the stack.
    ///
    /// From: void lua_pushboolean(lua_State *L, int b);
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_pushboolean
    /// Stack Behavior: [-0, +1, -]
    pub fn pushBoolean(lua: *Lua, value: bool) void {
        c.lua_pushboolean(asState(lua), @intFromBool(value));
    }

    /// Pushes the integer with value n onto the stack.
    ///
    /// From: void lua_pushinteger(lua_State *L, lua_Integer n);
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_pushinteger
    /// Stack Behavior: [-0, +1, -]
    pub fn pushInteger(lua: *Lua, n: Lua.Integer) void {
        c.lua_pushinteger(asState(lua), @intCast(n));
    }

    /// Pushes the floating point number with value n onto the stack.
    ///
    /// From: void lua_pushnumber(lua_State *L, lua_Number n);
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_pushnumber
    /// Stack Behavior: [-0, +1, -]
    pub fn pushNumber(lua: *Lua, n: Lua.Number) void {
        c.lua_pushnumber(asState(lua), @floatCast(n));
    }

    /// Pops n elements from the stack.
    ///
    /// From: void lua_pop(lua_State *L, int n);
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_pop
    /// Stack Behavior: [-n, +0, -]
    pub fn pop(lua: *Lua, n: i32) void {
        c.lua_pop(asState(lua), n);
    }
};

test "Lua can be initialized with an allocator" {
    const lua = Lua.init(std.testing.allocator);
    defer (lua catch unreachable).deinit();

    try std.testing.expect(lua != error.OutOfMemory);
}

test "Lua returns error when allocation fails" {
    const lua = Lua.init(std.testing.failing_allocator);
    try std.testing.expect(lua == error.OutOfMemory);
}

test "Lua type checking functions should work for an empty stack." {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    try std.testing.expect(lua.typeOf(1) == Lua.Type.None);
    try std.testing.expect(lua.isNone(1));
    try std.testing.expect(lua.isNoneOrNil(1));

    try std.testing.expect(!lua.isNil(1));
    try std.testing.expect(!lua.isBoolean(1));
    try std.testing.expect(!lua.isCFunction(1));
    try std.testing.expect(!lua.isFunction(1));
    try std.testing.expect(!lua.isLightUserdata(1));
    try std.testing.expect(!lua.isNumber(1));
    try std.testing.expect(!lua.isString(1));
    try std.testing.expect(!lua.isTable(1));
    try std.testing.expect(!lua.isThread(1));
    try std.testing.expect(!lua.isUserdata(1));
}

test "Lua type checking functions return true when stack contains value" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    lua.pushNil();
    try std.testing.expect(lua.typeOf(1) == Lua.Type.Nil);
    try std.testing.expect(lua.isNil(1));
    try std.testing.expect(lua.isNoneOrNil(1));
    try std.testing.expect(!(lua.typeOf(1) == Lua.Type.None));
    try std.testing.expect(!lua.isNone(1));
    lua.pop(1);

    lua.pushBoolean(true);
    try std.testing.expect(lua.typeOf(1) == Lua.Type.Boolean);
    try std.testing.expect(lua.isBoolean(1));
    try std.testing.expect(!lua.isNil(1));
    try std.testing.expect(!lua.isNoneOrNil(1));
    try std.testing.expect(!lua.isNone(1));
    try std.testing.expect(!lua.isCFunction(1));
    try std.testing.expect(!lua.isFunction(1));
    try std.testing.expect(!lua.isLightUserdata(1));
    try std.testing.expect(!lua.isNumber(1));
    try std.testing.expect(!lua.isString(1));
    try std.testing.expect(!lua.isTable(1));
    try std.testing.expect(!lua.isThread(1));
    try std.testing.expect(!lua.isUserdata(1));
    lua.pop(1);

    lua.pushInteger(42);
    try std.testing.expect(lua.typeOf(1) == Lua.Type.Number);
    try std.testing.expect(lua.isNumber(1));
    try std.testing.expect(lua.isString(1));
    try std.testing.expect(!lua.isNil(1));
    try std.testing.expect(!lua.isNoneOrNil(1));
    try std.testing.expect(!lua.isNone(1));
    try std.testing.expect(!lua.isBoolean(1));
    try std.testing.expect(!lua.isCFunction(1));
    try std.testing.expect(!lua.isFunction(1));
    try std.testing.expect(!lua.isLightUserdata(1));
    try std.testing.expect(!lua.isTable(1));
    try std.testing.expect(!lua.isThread(1));
    try std.testing.expect(!lua.isUserdata(1));
    lua.pop(1);

    lua.pushNumber(42.4);
    try std.testing.expect(lua.typeOf(1) == Lua.Type.Number);
    try std.testing.expect(lua.isNumber(1));
    try std.testing.expect(lua.isString(1));
    try std.testing.expect(!lua.isNil(1));
    try std.testing.expect(!lua.isNoneOrNil(1));
    try std.testing.expect(!lua.isNone(1));
    try std.testing.expect(!lua.isBoolean(1));
    try std.testing.expect(!lua.isCFunction(1));
    try std.testing.expect(!lua.isFunction(1));
    try std.testing.expect(!lua.isLightUserdata(1));
    try std.testing.expect(!lua.isTable(1));
    try std.testing.expect(!lua.isThread(1));
    try std.testing.expect(!lua.isUserdata(1));
    lua.pop(1);

    try std.testing.expectEqualSlices(u8, "no value", lua.typeName(Lua.Type.None));
    try std.testing.expectEqualSlices(u8, "nil", lua.typeName(Lua.Type.Nil));
    try std.testing.expectEqualSlices(u8, "boolean", lua.typeName(Lua.Type.Boolean));
    try std.testing.expectEqualSlices(u8, "userdata", lua.typeName(Lua.Type.Userdata));
    try std.testing.expectEqualSlices(u8, "number", lua.typeName(Lua.Type.Number));
    try std.testing.expectEqualSlices(u8, "string", lua.typeName(Lua.Type.String));
    try std.testing.expectEqualSlices(u8, "table", lua.typeName(Lua.Type.Table));
    try std.testing.expectEqualSlices(u8, "function", lua.typeName(Lua.Type.Function));
    try std.testing.expectEqualSlices(u8, "userdata", lua.typeName(Lua.Type.Light_userdata));
    try std.testing.expectEqualSlices(u8, "thread", lua.typeName(Lua.Type.Thread));
}
