const std = @import("std");
const testing = std.testing;

const c = @import("c");
fn asState(lua: *Lua) *c.lua_State {
    return @ptrCast(lua);
}

const aa = @import("allocator_adapter.zig");

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
        LightUserdata = c.LUA_TLIGHTUSERDATA,
        Number = c.LUA_TNUMBER,
        String = c.LUA_TSTRING,
        Table = c.LUA_TTABLE,
        Function = c.LUA_TFUNCTION,
        Userdata = c.LUA_TUSERDATA,
        Thread = c.LUA_TTHREAD,
    };

    const MaxStackSize = c.LUAI_MAXCSTACK;

    /// Creates a new Lua state with the provided allocator.
    ///
    /// The allocator is copied to the heap to ensure a stable address, as Lua requires
    /// the allocator to remain valid for the lifetime of the state. This copy is freed
    /// when deinit() is called.
    ///
    /// Caller owns the returned Lua state and must call deinit() to free resources.
    ///
    pub fn init(alloc: std.mem.Allocator) error{OutOfMemory}!*Lua {
        // alloc could be stack-allocated by the caller, but Lua requires a stable address.
        // We will create a pinned copy of the allocator on the heap.
        const ud = try alloc.create(aa.UserData);
        errdefer alloc.destroy(ud);
        ud.alloc = alloc;

        const lua: ?*Lua = @ptrCast(c.lua_newstate(aa.alloc, ud));
        return if (lua) |p| p else error.OutOfMemory;
    }

    /// Returns the memory-allocation function and user data configured in the given lua instance.
    /// If userdata is not NULL, Lua internally saves the user data pointer passed to lua_newstate.
    ///
    /// From: lua_Alloc lua_getallocf(lua_State *L, void **ud);
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_getallocf
    /// Stack Behavior: [-0, +0, -]
    fn getAllocF(lua: *Lua) aa.AdapterData {
        var ad: aa.AdapterData = undefined;
        const alloc_fn = c.lua_getallocf(@ptrCast(lua), @ptrCast(&ad.userdata));
        ad.alloc_fn = @ptrCast(alloc_fn);
        return ad;
    }

    /// Changes the allocator function of the lua instance.
    /// Changing the user data is currently prohibited. User data specified in the input will be ignored.
    ///
    /// From: void lua_setallocf(lua_State *L, lua_Alloc f, void *ud);
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_setallocf
    /// Stack Behavior: [-0, +0, -]
    fn setAllocF(lua: *Lua, f: *const aa.AllocFn) void {
        const current = lua.getAllocF();
        c.lua_setallocf(asState(lua), f, current.userdata);
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
        const ad = lua.getAllocF();

        c.lua_close(@ptrCast(lua));

        if (ad.userdata) |ud| {
            ud.alloc.destroy(ud);
        }
    }

    /// Ensures that there are at least `extra` free stack slots in the stack by allocating additional slots. Returns
    /// false if it cannot grow the stack to that size. This function never shrinks the stack;
    /// if the stack is already larger than the new size, it is left unchanged.
    ///
    /// From: int lua_checkstack(lua_State *L, int extra);
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_checkstack
    /// Stack Behavior: [-0, +0, -]
    pub fn checkStack(lua: *Lua, extra: i32) error{ OutOfMemory, StackOverflow }!void {
        const state = asState(lua);
        const size: i32 = @intCast(c.lua_gettop(state));
        if (size + extra > MaxStackSize) {
            return error.StackOverflow;
        }
        if (0 == c.lua_checkstack(asState(lua), @intCast(extra))) {
            return error.OutOfMemory;
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
        return lua.typeOf(index) == Lua.Type.LightUserdata;
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
        return c.lua_pushnil(asState(lua));
    }

    /// Pushes a boolean value with the given value onto the stack.
    ///
    /// From: void lua_pushboolean(lua_State *L, int b);
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_pushboolean
    /// Stack Behavior: [-0, +1, -]
    pub fn pushBoolean(lua: *Lua, value: bool) void {
        return c.lua_pushboolean(asState(lua), @intFromBool(value));
    }

    /// Errors indicating the actual type of a value found on the stack when attempting to find a boolean.
    pub const NotBooleanError = error{
        NoneIsNotBoolean,
        NilIsNotBoolean,
        LightUserdataIsNotBoolean,
        NumberIsNotBoolean,
        StringIsNotBoolean,
        TableIsNotBoolean,
        FunctionIsNotBoolean,
        UserdataIsNotBoolean,
        ThreadIsNotBoolean,
    };

    /// Converts the Lua value at the given acceptable index to a boolean with strict type checking. Returns `true`
    /// when the stack contains a `true` boolean value at the specified index. Returns `false` when the stack contains
    /// a `false` boolean value at the specified index. Otherwise an error indicating the type of unexpected value found
    /// on the stack at the specified index.
    ///
    /// Callers may use `toBoolean()` when seeking only to check the "truthyness" of the value on the stack at the
    /// specified index.
    ///
    /// (zig-luajit extension method)
    /// Stack Behavior: [-0, +0, -]
    pub fn toBooleanStrict(lua: *Lua, index: i32) NotBooleanError!bool {
        return switch (lua.typeOf(index)) {
            .Boolean => lua.toBoolean(index),

            .None => error.NoneIsNotBoolean,
            .Nil => error.NilIsNotBoolean,
            .LightUserdata => error.LightUserdataIsNotBoolean,
            .Number => error.NumberIsNotBoolean,
            .String => error.StringIsNotBoolean,
            .Table => error.TableIsNotBoolean,
            .Function => error.FunctionIsNotBoolean,
            .Userdata => error.UserdataIsNotBoolean,
            .Thread => error.ThreadIsNotBoolean,
        };
    }

    /// Converts the Lua value at the given acceptable index to a boolean. This function checks for the
    /// "truthyness" of the value on the stack. Returns `true` for any Lua value different from false and nil; otherwise
    /// returns `false`. Returns `false` when called with a non-valid index.
    ///
    /// Callers may use `toBooleanStrict()` when seeking only to return the content of a boolean value on the stack.
    /// Callers may also use `typeOf()` or `isBoolean()` to check the value on the stack before evaluating its value.
    ///
    /// From: int lua_toboolean(lua_State *L, int index);
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_toboolean
    /// Stack Behavior: [-0, +0, -]
    pub fn toBoolean(lua: *Lua, index: i32) bool {
        return 1 == c.lua_toboolean(asState(lua), index);
    }

    /// Pushes the integer with value n onto the stack.
    ///
    /// From: void lua_pushinteger(lua_State *L, lua_Integer n);
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_pushinteger
    /// Stack Behavior: [-0, +1, -]
    pub fn pushInteger(lua: *Lua, n: Lua.Integer) void {
        return c.lua_pushinteger(asState(lua), @intCast(n));
    }

    /// Pushes the floating point number with value n onto the stack.
    ///
    /// From: void lua_pushnumber(lua_State *L, lua_Number n);
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_pushnumber
    /// Stack Behavior: [-0, +1, -]
    pub fn pushNumber(lua: *Lua, n: Lua.Number) void {
        return c.lua_pushnumber(asState(lua), @floatCast(n));
    }

    /// Pushes the zero-terminated string onto the stack. Lua makes (or reuses) an internal copy of the given string,
    /// so the provided slice can be freed or reused immediately after the function returns. The given string cannot
    /// contain embedded zeros; it is assumed to end at the first zero ('\x00') byte.
    ///
    /// From: void lua_pushstring(lua_State *L, const char *s);
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_pushstring
    /// Stack Behavior: [-0, +1, m]
    pub fn pushString(lua: *Lua, string: [*:0]const u8) void {
        return c.lua_pushstring(asState(lua), @ptrCast(string));
    }

    /// Errors indicating the actual type of a value found on the stack when attempting to find a string.
    /// Numbers are implicitly converted to strings and this conversion is not defined as an error by the underlying API.
    pub const NotStringError = error{
        NoneIsNotString,
        NilIsNotString,
        BooleanIsNotString,
        LightUserdataIsNotString,
        TableIsNotString,
        FunctionIsNotString,
        UserdataIsNotString,
        ThreadIsNotString,
    };

    /// Converts the Lua value at the given acceptable index to a string. The value at the specified index
    /// must be a string or a number. If the value is a number, this function also changes the actual value
    /// in the stack to a string. If the value at the specified index is not a string or a number, an error
    /// will be returned.
    ///
    /// Returns a slice of a string inside the Lua instance. This string will not contain any zero ('\x00')
    /// bytes except for the terminating byte. Because Lua has garbage collection, there is no
    /// guarantee that the returned slice will be valid when the corresponding value is removed from the stack.
    ///
    /// Callers should avoid using `toString()` while traversing tables, since this function may change the value
    /// on the stack and alter the behavior of (or break) the traversal.
    ///
    /// From: const char *lua_tostring(lua_State *L, int index);
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_tostring
    /// Stack Behavior: [-0, +0, m]
    pub fn toString(lua: *Lua, index: i32) error{ValueNotConvertableToString}![*:0]const u8 {
        const string: ?[*:0]const u8 = c.lua_tolstring(asState(lua), index, null);
        if (string) |s| {
            return s;
        } else {
            return typeIsNotString(lua.typeOf(index));
        }
    }

    /// Pushes the bytes in the given slice onto the stack as a string. Lua makes (or reuses) an internal
    /// copy of the given string, so the provided slice may freed or reused immediately after the function returns.
    /// The string may contain embedded zeros, it is not interpreted as a c-style string ending at the first zero.
    ///
    /// From: void lua_pushlstring(lua_State *L, const char *s, size_t len);
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_pushlstring
    /// Stack Behavior: [-0, +1, m]
    pub fn pushLString(lua: *Lua, string: []const u8) void {
        return c.lua_pushlstring(asState(lua), @ptrCast(string.ptr), @intCast(string.len));
    }

    /// Converts the Lua value at the given acceptable index to a string. The value at the specified index
    /// must be a string or a number. If the value is a number, this function also changes the actual value
    /// in the stack to a string. If the value at the specified index is not a string or a number, an error
    /// will be returned.
    ///
    /// Returns zero-terminated slice pointing to a string inside the Lua instance. This string may contain
    /// any number of zero ('\x00') bytes within it in addition to the terminating byte. Because Lua has garbage
    /// collection, there is no guarantee that the returned slice will be valid when the corresponding value
    /// is removed from the stack.
    ///
    /// Callers should avoid using `toString()` while traversing tables, since this function may change the value
    /// on the stack and alter the behavior of (or break) the traversal.
    ///
    /// From: const char *lua_tolstring(lua_State *L, int index, size_t *len);
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_tolstring
    /// Stack Behavior: [-0, +0, m]
    pub fn toLString(lua: *Lua, index: i32) NotStringError![:0]const u8 {
        var len: usize = undefined;
        const string: ?[*]const u8 = c.lua_tolstring(asState(lua), index, &len);
        if (string) |s| {
            return s[0..len :0];
        } else {
            return typeIsNotString(lua.typeOf(index));
        }
    }

    fn typeIsNotString(t: Lua.Type) NotStringError {
        return switch (t) {
            .Number, .String => unreachable,

            .None => error.NoneIsNotString,
            .Nil => error.NilIsNotString,
            .Boolean => error.BooleanIsNotString,
            .LightUserdata => error.LightUserdataIsNotString,
            .Table => error.TableIsNotString,
            .Function => error.FunctionIsNotString,
            .Userdata => error.UserdataIsNotString,
            .Thread => error.ThreadIsNotString,
        };
    }

    /// Pops n elements from the stack.
    ///
    /// From: void lua_pop(lua_State *L, int n);
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_pop
    /// Stack Behavior: [-n, +0, -]
    pub fn pop(lua: *Lua, n: i32) void {
        return c.lua_pop(asState(lua), n);
    }

    /// Moves the top element into the given valid index, shifting up the elements above this index to open space.
    /// Cannot be called with a pseudo-index, because a pseudo-index is not an actual stack position.
    ///
    /// From: void lua_insert(lua_State *L, int index);
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_insert
    /// Stack Behavior: [-1, +1, -]
    pub fn insert(lua: *Lua, index: i32) void {
        return c.lua_insert(asState(lua), index);
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

    lua.pushNumber(125);
    lua.pushBoolean(true);
    lua.pushNil();
    try std.testing.expect(lua.isNil(-1));
    try std.testing.expect(lua.isBoolean(-2));
    try std.testing.expect(lua.isNumber(-3));
    try std.testing.expect(lua.isNil(3));
    try std.testing.expect(lua.isBoolean(2));
    try std.testing.expect(lua.isNumber(1));
    lua.pop(2);
    try std.testing.expect(lua.isNumber(-1));
    try std.testing.expect(lua.isNumber(1));
    lua.pop(1);

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

    lua.pushString("abc");
    try std.testing.expect(lua.isString(1));
    lua.pop(1);

    lua.pushLString("abc");
    try std.testing.expect(lua.isString(1));
    lua.pop(1);

    try std.testing.expectEqualSlices(u8, "no value", lua.typeName(Lua.Type.None));
    try std.testing.expectEqualSlices(u8, "nil", lua.typeName(Lua.Type.Nil));
    try std.testing.expectEqualSlices(u8, "boolean", lua.typeName(Lua.Type.Boolean));
    try std.testing.expectEqualSlices(u8, "userdata", lua.typeName(Lua.Type.Userdata));
    try std.testing.expectEqualSlices(u8, "number", lua.typeName(Lua.Type.Number));
    try std.testing.expectEqualSlices(u8, "string", lua.typeName(Lua.Type.String));
    try std.testing.expectEqualSlices(u8, "table", lua.typeName(Lua.Type.Table));
    try std.testing.expectEqualSlices(u8, "function", lua.typeName(Lua.Type.Function));
    try std.testing.expectEqualSlices(u8, "userdata", lua.typeName(Lua.Type.LightUserdata));
    try std.testing.expectEqualSlices(u8, "thread", lua.typeName(Lua.Type.Thread));
}

test "toBoolean and toBooleanStrict" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    try std.testing.expect(!lua.toBoolean(1));
    try std.testing.expectError(error.NoneIsNotBoolean, lua.toBooleanStrict(1));

    lua.pushBoolean(true);
    try std.testing.expect(lua.toBoolean(1));
    try std.testing.expect(try lua.toBooleanStrict(1));
    lua.pop(1);

    lua.pushBoolean(false);
    try std.testing.expect(!lua.toBoolean(1));
    try std.testing.expect(!try lua.toBooleanStrict(1));
    lua.pop(1);

    lua.pushNil();
    try std.testing.expect(!lua.toBoolean(1));
    try std.testing.expectError(error.NilIsNotBoolean, lua.toBooleanStrict(1));
    lua.pop(1);

    lua.pushNumber(42);
    try std.testing.expect(lua.toBoolean(1));
    try std.testing.expectError(error.NumberIsNotBoolean, lua.toBooleanStrict(1));
    lua.pop(1);

    lua.pushString("Hello, world!");
    try std.testing.expect(lua.toBoolean(1));
    try std.testing.expectError(error.StringIsNotBoolean, lua.toBooleanStrict(1));
    lua.pop(1);
}

test {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    lua.pushInteger(42);
    lua.pushBoolean(true);
    lua.insert(-2);
    try std.testing.expect(lua.isBoolean(1) and lua.isBoolean(-2));
    try std.testing.expect(lua.isNumber(2) and lua.isNumber(-1));
    lua.pop(2);
}

test "zero terminated strings" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    const expected: [*:0]const u8 = "abc\x00def";

    lua.pushString(expected);
    const actual = try lua.toString(1);
    const actual_len = std.mem.indexOfSentinel(u8, 0, actual);
    const expected_len = std.mem.indexOfSentinel(u8, 0, expected);
    try std.testing.expect(expected_len == actual_len);
    try std.testing.expectEqualSlices(u8, expected[0..expected_len :0], actual[0..actual_len :0]);
    lua.pop(1);
}

test "slices strings" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    const expected: [:0]const u8 = "abc\x00def";

    lua.pushLString(expected);
    const actual = try lua.toLString(1);
    try std.testing.expect(expected.len == actual.len);
    try std.testing.expectEqualSlices(u8, expected, actual);
    lua.pop(1);
}

test "slices strings to terminated strings" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    const expected: [:0]const u8 = "abc\x00def";

    lua.pushLString(expected);
    const actual = try lua.toString(1);
    const actual_len = std.mem.indexOfSentinel(u8, 0, actual);
    try std.testing.expect(expected.len != actual_len);
    try std.testing.expect(expected.len == 7);
    try std.testing.expect(actual_len == 3);
    lua.pop(1);
}

test "checkStack should return StackOverflow when requested space is too large" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    try std.testing.expectError(error.StackOverflow, lua.checkStack(9000));
}

test "checkStack should return OOM when allocation fails." {
    const lua = try Lua.init(std.testing.allocator);
    lua.setAllocF(aa.fail_alloc);
    defer {
        lua.setAllocF(aa.alloc);
        lua.deinit();
    }

    try std.testing.expectError(error.OutOfMemory, lua.checkStack(100));
}
