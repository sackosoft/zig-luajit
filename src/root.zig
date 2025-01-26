//! Copyright (c) 2024-2025 Theodore Sackos
//! SPDX-License-Identifier: AGPL-3.0-or-later

const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;

const mode = @import("builtin").mode;

const c = @import("c");
fn asState(lua: *Lua) *c.lua_State {
    return @ptrCast(lua);
}

const aa = @import("allocator_adapter.zig");

/// A Lua state represents the entire context of a Lua interpreter.
/// Each state is completely independent and has no global variables.
///
/// The state must be initialized with `init()` and cleaned up with `deinit()`.
/// All Lua operations require a pointer to a state as their first argument,
/// except for `init()` which creates a new state.
///
/// From: `typedef struct lua_State lua_State;`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_State
pub const Lua = opaque {
    pub const Number = c.LUA_NUMBER;
    pub const Integer = c.LUA_INTEGER;
    pub const Type = enum(i5) {
        none = c.LUA_TNONE,
        nil = c.LUA_TNIL,
        boolean = c.LUA_TBOOLEAN,
        light_userdata = c.LUA_TLIGHTUSERDATA,
        number = c.LUA_TNUMBER,
        string = c.LUA_TSTRING,
        table = c.LUA_TTABLE,
        function = c.LUA_TFUNCTION,
        userdata = c.LUA_TUSERDATA,
        thread = c.LUA_TTHREAD,
    };

    const LuaStatus = enum(i32) {
        OK = 0,
        YIELD = 1,
        ERRRUN = 2,
        ERRSYNTAX = 3,
        ERRMEM = 4,
        ERRERR = 5,
    };

    const MaxStackSize: i32 = c.LUAI_MAXCSTACK;

    /// Used as the value for `nresults` to return all results from the function on the stack when invoking
    /// `call()` or `protectedCall()`.
    ///
    /// Usually, when using `call()` or `protectedCall()`, the function results are pushed onto the stack when
    /// the function returns, then the number of results is adjusted to the value of `nresults` specified by the
    /// caller. By using `Lua.MultipleReturn`, all results from the function are left on the stack.
    pub const MultipleReturn: i32 = c.LUA_MULTRET;

    /// Creates a new Lua state with the provided allocator.
    ///
    /// The allocator is copied to the heap to ensure a stable address, as Lua requires
    /// the allocator to remain valid for the lifetime of the state. This copy is freed
    /// when `deinit()` is called.
    ///
    /// Caller owns the returned Lua state and must call `deinit()` to free resources.
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
    /// If userdata is not null, Lua internally saves the user data pointer passed to `lua_newstate`.
    ///
    /// From: `lua_Alloc lua_getallocf(lua_State *L, void **ud);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_getallocf
    /// Stack Behavior: `[-0, +0, -]`
    fn getAllocF(lua: *Lua) aa.AdapterData {
        var ad: aa.AdapterData = undefined;
        const alloc_fn = c.lua_getallocf(@ptrCast(lua), @ptrCast(&ad.userdata));
        ad.alloc_fn = @ptrCast(alloc_fn);
        return ad;
    }

    /// Changes the allocator function of the lua instance.
    /// Changing the user data is currently prohibited. User data specified in the input will be ignored.
    ///
    /// From: `void lua_setallocf(lua_State *L, lua_Alloc f, void *ud);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_setallocf
    /// Stack Behavior: `[-0, +0, -]`
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
    /// false if it cannot grow the stack to that size. This function never shrinks the stack; if the stack is already
    /// larger than the new size, it is left unchanged.
    ///
    /// From: `int lua_checkstack(lua_State *L, int extra);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_checkstack
    /// Stack Behavior: `[-0, +0, -]`
    pub fn checkStack(lua: *Lua, extra: i32) error{ OutOfMemory, StackOverflow }!void {
        assert(extra >= 0);

        const state = asState(lua);
        const size: i32 = @intCast(c.lua_gettop(state));
        if (size + extra > MaxStackSize) {
            return error.StackOverflow;
        }
        if (0 == c.lua_checkstack(asState(lua), @intCast(extra))) {
            return error.OutOfMemory;
        }
    }

    /// Returns the name of the type encoded by the value `t`.
    /// Caller *does not* own the returned slice.
    ///
    /// From: `const char *lua_typename(lua_State *L, int tp);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_typename
    /// Stack Behavior: `[-0, +0, -]`
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
        assert(index >= 0);

        return type_to_name[@as(usize, @intCast(index))];
    }

    /// Explicitly marks stack index usage as intentionally unchecked. Used when the Lua C API behavior
    /// is well-defined even for invalid indices, such as `typeOf()` returning `Lua.Type.None` when
    /// accessing an invalid or unacceptable index.
    ///
    /// This function serves as documentation and serves no functional purpose. It should be used to help
    /// distinguish cases where stack index checking was forgotten or not considered by the developer from
    /// cases where stack index checking was considered by the develop and decidied to not be applied.
    fn skipIndexValidation(lua: *Lua, index: i32, justification: []const u8) void {
        _ = lua;
        _ = index;
        _ = justification;
    }

    /// Validates that the given stack index could point to a valid stack position. Catches common errors like
    /// using index 0 or indices beyond stack bounds. This validation has no effect in release builds with safety
    /// checking disabled.
    ///
    /// Should be called before operations that have undefined behavior with invalid indices, such as `toNumber()`
    /// or `toString()`.
    fn validateStackIndex(lua: *Lua, index: i32) void {
        assert(index != 0);

        // Make sure we only run these checks in safety-checked build modes.
        if (mode == .ReleaseSafe or mode == .Debug) {
            if (index <= c.LUA_REGISTRYINDEX) {
                const max_upvalues_count = 255;
                assert(@as(i32, @intCast(c.LUA_GLOBALSINDEX - max_upvalues_count)) <= index); // Safety check failed: pseudo-index exceeds maximum number of upvalues (255). This can also happen if your stack index has been corrupted and become a very large negative number.
            } else if (index < 0) {
                assert(-lua.getTop() <= index); // Safety check failed: Stack index goes below the bottom of the stack.

            } else {
                assert(index <= lua.getTop()); // Safety check failed: Stack index exceeds the top of the stack.
            }
        }
    }

    /// Returns the type of the value in the specified index on the stack, or `Lua.Type.None` if the
    /// index is not valid.
    ///
    /// Note: This function was renamed from `type` due to naming conflicts with Zig's `type` keyword.
    ///
    /// From: `int lua_type(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_type
    /// Stack Behavior: `[-0, +0, -]`
    pub fn typeOf(lua: *Lua, index: i32) Lua.Type {
        lua.skipIndexValidation(
            index,
            "typeOf() safely returns `None` when the index is not valid (required by Lua spec).",
        );

        const t = c.lua_type(asState(lua), index);
        return @enumFromInt(t);
    }

    /// Returns true if the given acceptable index is not valid (that is, it refers to an element outside the
    /// current stack) or if the value at this index is nil, and false otherwise.
    ///
    /// From: `int lua_isnoneornil(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_isnoneornil
    /// Stack Behavior: `[-0, +0, -]`
    pub fn isNoneOrNil(lua: *Lua, index: i32) bool {
        lua.skipIndexValidation(
            index,
            "isNoneOrNil() safely returns `true` when the index is not valid (required by Lua spec).",
        );

        return lua.typeOf(index) == Lua.Type.none or lua.typeOf(index) == Lua.Type.nil;
    }

    /// Returns true if the given acceptable index is not valid (that is, it refers to an element outside the
    /// current stack), and false otherwise.
    ///
    /// From: `int lua_isnone(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_isnone
    /// Stack Behavior: `[-0, +0, -]`
    pub fn isNone(lua: *Lua, index: i32) bool {
        lua.skipIndexValidation(
            index,
            "isNone() safely returns `true` when the index is not valid (required by Lua spec).",
        );

        return lua.typeOf(index) == Lua.Type.none;
    }

    /// Returns true if the value at the given acceptable index is nil, and false otherwise.
    ///
    /// From: `int lua_isnil(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_isnil
    /// Stack Behavior: `[-0, +0, -]`
    pub fn isNil(lua: *Lua, index: i32) bool {
        lua.validateStackIndex(index);

        return lua.typeOf(index) == Lua.Type.nil;
    }

    /// Returns true if the value at the given acceptable index has type boolean, false otherwise.
    ///
    /// From: `int lua_isboolean(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_isboolean
    /// Stack Behavior: `[-0, +0, -]`
    pub fn isBoolean(lua: *Lua, index: i32) bool {
        lua.validateStackIndex(index);

        return lua.typeOf(index) == Lua.Type.boolean;
    }

    /// Returns true if the value at the given acceptable index is a function (either C or Lua), and false otherwise.
    ///
    /// From: `int lua_isfunction(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_isfunction
    /// Stack Behavior: `[-0, +0, -]`
    pub fn isFunction(lua: *Lua, index: i32) bool {
        lua.validateStackIndex(index);

        return lua.typeOf(index) == Lua.Type.function;
    }

    /// Returns true if the value at the given acceptable index is a light userdata, false otherwise.
    ///
    /// From: `int lua_islightuserdata(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_islightuserdata
    /// Stack Behavior: `[-0, +0, -]`
    pub fn isLightUserdata(lua: *Lua, index: i32) bool {
        lua.validateStackIndex(index);

        return lua.typeOf(index) == Lua.Type.light_userdata;
    }

    /// Returns true if the value at the given acceptable index is a table, false otherwise.
    ///
    /// From: `int lua_istable(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_istable
    /// Stack Behavior: `[-0, +0, -]`
    pub fn isTable(lua: *Lua, index: i32) bool {
        lua.validateStackIndex(index);

        return lua.typeOf(index) == Lua.Type.table;
    }

    /// Returns true if the value at the given acceptable index is a thread, and false otherwise.
    ///
    /// From: `int lua_isthread(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_isthread
    /// Stack Behavior: `[-0, +0, -]`
    pub fn isThread(lua: *Lua, index: i32) bool {
        lua.validateStackIndex(index);

        return lua.typeOf(index) == Lua.Type.thread;
    }

    /// Returns true if the value at the given acceptable index is a number and an integer; that is, the number
    /// has no fractional part.
    ///
    /// (zig-luajit extension method)
    /// Stack Behavior: `[-0, +0, -]`
    pub fn isInteger(lua: *Lua, index: i32) bool {
        lua.validateStackIndex(index);

        return lua.isNumber(index) //
        and block: {
            const n = lua.toNumber(index);
            break :block n == @as(Lua.Number, @floatFromInt(@as(Lua.Integer, @intFromFloat(n))));
        };
    }

    /// Returns true if the value at the given acceptable index is a number or a string convertible to a number,
    /// false otherwise.
    ///
    /// From: `int lua_isnumber(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_isnumber
    /// Stack Behavior: `[-0, +0, -]`
    pub fn isNumber(lua: *Lua, index: i32) bool {
        lua.validateStackIndex(index);

        return 1 == c.lua_isnumber(asState(lua), index);
    }

    /// Returns true if the value at the given acceptable index is a string or a number
    /// (which is always convertible to a string), and false otherwise.
    ///
    /// From: `int lua_isstring(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_isstring
    /// Stack Behavior: `[-0, +0, -]`
    pub fn isString(lua: *Lua, index: i32) bool {
        lua.validateStackIndex(index);

        return 1 == c.lua_isstring(asState(lua), index);
    }

    /// Returns `true` if the value at the given acceptable index is a C function, returns `false`
    /// otherwise.
    ///
    /// From: `int lua_iscfunction(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_iscfunction
    /// Stack Behavior: `[-0, +0, -]`
    pub fn isCFunction(lua: *Lua, index: i32) bool {
        lua.validateStackIndex(index);

        return 1 == c.lua_iscfunction(asState(lua), index);
    }

    /// Returns true if the value at the given acceptable index is a userdata
    /// (either full or light), and false otherwise.
    ///
    /// From: `int lua_isuserdata(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_isuserdata
    /// Stack Behavior: `[-0, +0, -]`
    pub fn isUserdata(lua: *Lua, index: i32) bool {
        lua.validateStackIndex(index);

        return 1 == c.lua_isuserdata(asState(lua), index);
    }

    /// Pushes a nil value onto the stack.
    ///
    /// From: `void lua_pushnil(lua_State *L);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_pushnil
    /// Stack Behavior: `[-0, +1, -]`
    pub fn pushNil(lua: *Lua) void {
        return c.lua_pushnil(asState(lua));
    }

    /// Pushes a boolean value with the given value onto the stack.
    ///
    /// From: `void lua_pushboolean(lua_State *L, int b);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_pushboolean
    /// Stack Behavior: `[-0, +1, -]`
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
    /// Stack Behavior: `[-0, +0, -]`
    pub fn toBooleanStrict(lua: *Lua, index: i32) NotBooleanError!bool {
        lua.skipIndexValidation(
            index,
            "toBooleanStrict() safely returns `error.NoneIsNotBoolean` when the index is not valid.",
        );

        return switch (lua.typeOf(index)) {
            .boolean => lua.toBoolean(index),

            .none => error.NoneIsNotBoolean,
            .nil => error.NilIsNotBoolean,
            .light_userdata => error.LightUserdataIsNotBoolean,
            .number => error.NumberIsNotBoolean,
            .string => error.StringIsNotBoolean,
            .table => error.TableIsNotBoolean,
            .function => error.FunctionIsNotBoolean,
            .userdata => error.UserdataIsNotBoolean,
            .thread => error.ThreadIsNotBoolean,
        };
    }

    /// Converts the Lua value at the given acceptable index to a boolean. This function checks for the
    /// "truthyness" of the value on the stack. Returns `true` for any Lua value different from false and nil; otherwise
    /// returns `false`. Returns `false` when called with a non-valid index.
    ///
    /// Callers may use `toBooleanStrict()` when seeking only to return the content of a boolean value on the stack.
    /// Callers may also use `typeOf()` or `isBoolean()` to check the value on the stack before evaluating its value.
    ///
    /// From: `int lua_toboolean(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_toboolean
    /// Stack Behavior: `[-0, +0, -]`
    pub fn toBoolean(lua: *Lua, index: i32) bool {
        lua.skipIndexValidation(
            index,
            "toBoolean() safely returns `false` when the index is not valid (required by Lua spec).",
        );

        return 1 == c.lua_toboolean(asState(lua), index);
    }

    /// Pushes the integer with value n onto the stack.
    ///
    /// From: `void lua_pushinteger(lua_State *L, lua_Integer n);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_pushinteger
    /// Stack Behavior: `[-0, +1, -]`
    pub fn pushInteger(lua: *Lua, n: Lua.Integer) void {
        return c.lua_pushinteger(asState(lua), @intCast(n));
    }

    /// Errors indicating the actual type of a value found on the stack when attempting to find a number.
    pub const NotNumberError = error{
        StringIsNotNumber,
        NoneIsNotNumber,
        NilIsNotNumber,
        BooleanIsNotNumber,
        LightUserdataIsNotNumber,
        TableIsNotNumber,
        FunctionIsNotNumber,
        UserdataIsNotNumber,
        ThreadIsNotNumber,
    };

    /// Converts the Lua value at the given acceptable index to the signed integral type `Lua.Integer`. If
    /// the value at the specified index on the stack is not an integer or number, an error is returned.
    ///
    /// (zig-luajit extension method)
    /// From: `lua_Integer lua_tointeger(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_tointeger
    /// Stack Behavior: `[-0, +0, -]`
    pub fn toIntegerStrict(lua: *Lua, index: i32) NotNumberError!Lua.Integer {
        lua.skipIndexValidation(
            index,
            "toIntegerStrict() safely returns `error.NoneIsNotNumber` when the index is not valid.",
        );

        const t = lua.typeOf(index);
        if (t == Lua.Type.number) {
            return c.lua_tointeger(asState(lua), index);
        } else {
            return typeIsNotNumber(t);
        }
    }

    fn typeIsNotNumber(t: Lua.Type) NotNumberError {
        return switch (t) {
            .number => unreachable,
            .string => error.StringIsNotNumber,
            .none => error.NoneIsNotNumber,
            .nil => error.NilIsNotNumber,
            .boolean => error.BooleanIsNotNumber,
            .light_userdata => error.LightUserdataIsNotNumber,
            .table => error.TableIsNotNumber,
            .function => error.FunctionIsNotNumber,
            .userdata => error.UserdataIsNotNumber,
            .thread => error.ThreadIsNotNumber,
        };
    }

    /// Converts the Lua value at the given acceptable index to the signed integral type `Lua.Integer`.
    ///
    /// Strings may be automatically coerced to integer (see https://www.lua.org/manual/5.1/manual.html#2.2.1).
    /// If the value at the specified index on the stack is not a string or a number, the value `0` is returned.
    /// If the value is a floating point number, it is truncated in some non-specified way.
    ///
    /// From: `lua_Integer lua_tointeger(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_tointeger
    /// Stack Behavior: `[-0, +0, -]`
    pub fn toInteger(lua: *Lua, index: i32) Lua.Integer {
        lua.validateStackIndex(index);

        return c.lua_tointeger(asState(lua), index);
    }

    /// Pushes the floating point number with value n onto the stack.
    ///
    /// From: `void lua_pushnumber(lua_State *L, lua_Number n);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_pushnumber
    /// Stack Behavior: `[-0, +1, -]`
    pub fn pushNumber(lua: *Lua, n: Lua.Number) void {
        return c.lua_pushnumber(asState(lua), @floatCast(n));
    }

    /// Converts the Lua value at the given acceptable index to a Number. If the value at the specified
    /// index is not an integer or a number, an error is returned.
    ///
    /// (zig-luajit extension method)
    /// From: `lua_Number lua_tonumber(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_tonumber
    /// Stack Behavior: `[-0, +0, -]`
    pub fn toNumberStrict(lua: *Lua, index: i32) NotNumberError!Lua.Number {
        lua.skipIndexValidation(
            index,
            "toNumberStrict() safely returns `error.NoneIsNotNumber` when the index is not valid.",
        );

        const t = lua.typeOf(index);
        if (t == Lua.Type.number) {
            return c.lua_tonumber(asState(lua), index);
        } else {
            return typeIsNotNumber(t);
        }
    }

    /// Converts the Lua value at the given acceptable index to a Number. The Lua value must be a number
    /// or a string convertible to a number (see https://www.lua.org/manual/5.1/manual.html#2.2.1);
    /// otherwise, returns 0.
    ///
    /// From: `lua_Number lua_tonumber(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_tonumber
    /// Stack Behavior: `[-0, +0, -]`
    pub fn toNumber(lua: *Lua, index: i32) Lua.Number {
        lua.validateStackIndex(index);

        return c.lua_tonumber(asState(lua), index);
    }

    /// Type for C functions that can be called by Lua. A C function follows a specific protocol for
    /// receiving arguments from and returning values to Lua via the stack.
    ///
    /// The function receives arguments from Lua in direct order on the stack.
    /// - The first argument is at index 1
    /// - lua_gettop(L) returns the total number of arguments
    ///
    /// To return values, the function pushes results onto the stack in direct order
    /// and returns the number of results. Any other values on the stack below the
    /// results will be discarded by Lua.
    ///
    /// From: `typedef int (*lua_CFunction) (lua_State *L);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_CFunction
    pub const CFunction = *const fn (lua: *Lua) callconv(.c) i32;

    /// Returns the pseudo-index to the specified up value of a C function closure.
    ///
    /// When a C function is created, it is possible to associate some values with it, thus creating a "closure"
    /// (see https://www.lua.org/manual/5.1/manual.html#lua_pushcclosure and https://www.lua.org/manual/5.1/manual.html#3.4).
    /// When this happens, the values are popped from the stack and managed by the Lua runtime. C functions may
    /// reference these "upvalues" by a pseudo-index returned by this function. These pseudo-indices are not
    /// references to the stack like other indices, instead, they are assocaited with the C function and managed
    /// by the Lua runtime.
    ///
    /// The first value associated with the function is at position `upvalueIndex(1)`, the second at
    /// `upvalueIndex(2)`, and so on. C closures support only 255 upvalues.
    ///
    /// From: `#define lua_upvalueindex(i)`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#3.4
    /// Stack Behavior: `[-0, 0, -]`
    pub fn upvalueIndex(lua: *Lua, index: u8) i32 {
        lua.skipIndexValidation(
            @intCast(index),
            "upvalueIndex() is type-restricted by the `u8` to a safe range.",
        );

        const globals_index: i32 = @intCast(c.LUA_GLOBALSINDEX);
        return @intCast(globals_index - index);
    }

    /// Pushes a C function onto the stack. This function receives a pointer to a C function and pushes
    /// onto the stack a Lua value of type function that, when called, invokes the corresponding C function.
    /// Any function to be registered in Lua must follow the correct protocol to receive its parameters
    /// and return its results (see https://www.lua.org/manual/5.1/manual.html#lua_CFunction).
    ///
    /// From: `void lua_pushcfunction(lua_State *L, lua_CFunction f);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_pushcfunction
    /// Stack Behavior: `[-0, +1, m]`
    pub fn pushCFunction(lua: *Lua, f: CFunction) void {
        return c.lua_pushcclosure(asState(lua), @ptrCast(f), 0);
    }

    /// Pushes a new C closure onto the stack. When a C function is created, it is possible to associate
    /// some values with it, thus creating a C closure (see https://www.lua.org/manual/5.1/manual.html#3.4);
    /// these values are then accessible to the function whenever it is called. To associate values with
    /// a C function, first these values should be pushed onto the stack (when there are multiple values,
    /// the first value is pushed first). Then lua_pushcclosure is called to create and push the C function
    /// onto the stack, with the argument n telling how many values should be associated with the function.
    /// lua_pushcclosure also pops these values from the stack. The maximum value for n is 255.
    ///
    /// From: `void lua_pushcclosure(lua_State *L, lua_CFunction fn, int n);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_pushcclosure
    /// Stack Behavior: `[-n, +1, m]`
    pub fn pushCClosure(lua: *Lua, f: CFunction, n: u8) void {
        return c.lua_pushcclosure(asState(lua), @ptrCast(f), @as(i32, @intCast(n)));
    }

    /// Pushes the zero-terminated string onto the stack. Lua makes (or reuses) an internal copy of the given string,
    /// so the provided slice can be freed or reused immediately after the function returns. The given string cannot
    /// contain embedded zeros; it is assumed to end at the first zero (`'\x00'`) byte.
    ///
    /// From: `void lua_pushstring(lua_State *L, const char *s);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_pushstring
    /// Stack Behavior: `[-0, +1, m]`
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
    /// From: `const char *lua_tostring(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_tostring
    /// Stack Behavior: `[-0, +0, m]`
    pub fn toString(lua: *Lua, index: i32) NotStringError![*:0]const u8 {
        lua.validateStackIndex(index);

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
    /// From: `void lua_pushlstring(lua_State *L, const char *s, size_t len);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_pushlstring
    /// Stack Behavior: `[-0, +1, m]`
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
    /// From: `const char *lua_tolstring(lua_State *L, int index, size_t *len);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_tolstring
    /// Stack Behavior: `[-0, +0, m]`
    pub fn toLString(lua: *Lua, index: i32) NotStringError![:0]const u8 {
        lua.validateStackIndex(index);

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
            .number, .string => unreachable,

            .none => error.NoneIsNotString,
            .nil => error.NilIsNotString,
            .boolean => error.BooleanIsNotString,
            .light_userdata => error.LightUserdataIsNotString,
            .table => error.TableIsNotString,
            .function => error.FunctionIsNotString,
            .userdata => error.UserdataIsNotString,
            .thread => error.ThreadIsNotString,
        };
    }

    /// Creates a new empty table and pushes it onto the stack. It is equivalent to calling `createTable` with
    /// initial array and hash table sizes of 0.
    ///
    /// From: `void lua_newtable(lua_State *L);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_newtable
    /// Stack Behavior: `[-0, +1, m]`
    pub fn newTable(lua: *Lua) void {
        return c.lua_newtable(asState(lua));
    }

    /// Creates a new empty table and pushes it onto the stack. The new table has space pre-allocated
    /// for `n_array` array elements and `n_hash` non-array elements. This pre-allocation is useful when you
    /// know exactly how many elements the table will have. Otherwise you can use the `newTable` function.
    ///
    /// From: `void lua_createtable(lua_State *L, int narr, int nrec);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_createtable
    /// Stack Behavior: `[-0, +1, m]`
    pub fn createTable(lua: *Lua, n_array: i32, n_hash: i32) void {
        assert(n_array >= 0);
        assert(n_hash >= 0);
        return c.lua_createtable(asState(lua), n_array, n_hash);
    }

    /// Pushes onto the stack the value `t[k]`, where `t` is the value at the given valid index and `k` is the value
    /// at the top of the stack. This function pops the key from the stack (putting the resulting value in its place).
    /// As in Lua, this function may trigger a metamethod for the "index" event
    /// (see https://www.lua.org/manual/5.1/manual.html#2.8).
    ///
    /// From: `void lua_gettable(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_gettable
    /// Stack Behavior: `[-1, +1, e]`
    pub fn getTable(lua: *Lua, index: i32) Lua.Type {
        lua.validateStackIndex(index);

        c.lua_gettable(asState(lua), index);
        return lua.typeOf(-1);
    }

    /// Similar to lua_gettable, but does a raw access (i.e., without metamethods).
    ///
    /// Note: This function was renamed from `rawget`.
    ///
    /// From: `void lua_rawget(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_rawget
    /// Stack Behavior: `[-1, +1, -]`
    pub fn getTableRaw(lua: *Lua, index: i32) Lua.Type {
        lua.validateStackIndex(index);

        c.lua_rawget(asState(lua), index);
        return lua.typeOf(-1);
    }

    /// Does the equivalent of `t[k] = v`, where `t` is the acceptable index of the table on the stack, `v` is
    /// the value at the top of the stack, and `k` is the value just below the top. This function pops both the
    /// key and the value from the stack. As in Lua, this function may trigger a metamethod for the "newindex"
    /// event (see https://www.lua.org/manual/5.1/manual.html#2.8).
    ///
    /// Example:
    /// ```zig
    /// lua.newTable();
    /// lua.pushInteger(1);
    /// lua.pushString("Hello, world!");
    /// lua.setTable(-3);
    /// std.debug.assert(1 == lua.getTop());
    /// std.debug.assert(lua.isTable());
    /// ```
    ///
    /// From: `void lua_settable(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_settable
    /// Stack Behavior: `[-2, +0, e]`
    pub fn setTable(lua: *Lua, index: i32) void {
        lua.validateStackIndex(index);
        assert(lua.isTable(index));

        return c.lua_settable(asState(lua), index);
    }

    /// Pops `n` elements from the stack.
    ///
    /// From: `void lua_pop(lua_State *L, int n);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_pop
    /// Stack Behavior: `[-n, +0, -]`
    pub fn pop(lua: *Lua, n: i32) void {
        assert(n >= 0);

        return c.lua_pop(asState(lua), n);
    }

    /// Returns the index of the top element in the stack. Because indices start at 1,
    /// this result is equal to the number of elements in the stack (and so 0 means an empty stack).
    ///
    /// From: `int lua_gettop(lua_State *L);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_gettop
    /// Stack Behavior: `[-0, +0, -]`
    pub fn getTop(lua: *Lua) i32 {
        return c.lua_gettop(asState(lua));
    }

    /// Moves the top element into the given valid index, shifting up the elements above this index to open space.
    /// Cannot be called with a pseudo-index, because a pseudo-index is not an actual stack position.
    ///
    /// From: `void lua_insert(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_insert
    /// Stack Behavior: `[-1, +1, -]`
    pub fn insert(lua: *Lua, index: i32) void {
        lua.validateStackIndex(index);

        return c.lua_insert(asState(lua), index);
    }

    /// Returns the "length" of the value at the given acceptable index:
    /// * for strings, this is the string length;
    /// * for numbers, after an implicit coversion to a string value this is the string length;
    /// * for tables, this is the result of the length operator ('#');
    /// * for userdata, this is the size of the block of memory allocated for the userdata;
    /// * for other values, it is 0.
    ///
    /// Note: This function was renamed from `objlen` for clarity and discoverability.
    ///
    /// From: `size_t lua_objlen(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_objlen
    /// Stack Behavior: `[-0, +0, -]`
    pub fn lengthOf(lua: *Lua, index: i32) usize {
        // This function can safely return 0 when the index is not valid, but I'd rather see callers
        // check the type to make that determination rather than rely on this implictly returning that.
        lua.validateStackIndex(index);

        return @intCast(c.lua_objlen(asState(lua), index));
    }

    /// Pops a key from the stack, and pushes a key-value pair from the table at the given index
    /// (the "next" pair after the given key) and returns `true`. If there are no more elements
    /// in the table, then lua_next returns `false` (and pushes nothing).
    ///
    /// Next is commonly used for doing a complete traversal over all elements of a table:
    /// ```zig
    /// // Assuming the table is at the top of the stack, we start by pushing nil, which cannot be a table key.
    /// lua.pushNil();
    /// while (lua.next(-2)) {
    ///     std.debug.print("The key is a '{s}'\n", .{lua.typeName(lua.typeOf(-2))});
    ///     std.debug.print("The value is a '{s}'\n", .{lua.typeName(lua.typeOf(-1))});
    ///
    ///     // Remove the 'value' from the stack, the key remains at the top for `next()` to find.
    ///     lua.pop(1);
    /// }
    /// ```
    ///
    /// While traversing a table, do not call `toString()` directly on a key, unless you know
    /// that the key is actually a string. Recall that `toString()` changes the value at the
    /// given index; this confuses the next call to lua_next.
    ///
    /// From: `int lua_next(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_next
    /// Stack Behavior: `[-1, +(2|0), e]`
    pub fn next(lua: *Lua, index: i32) bool {
        lua.validateStackIndex(index);

        return 1 == c.lua_next(asState(lua), index);
    }

    /// Represents the kinds of errors that calling a Lua function may result in.
    pub const CallError = error{
        /// Used when the execution of Lua code encounters an error.
        Runtime,

        /// Used when Lua is unable to allocate required memory.
        OutOfMemory,
    };

    pub const ProtectedCallError = error{
        /// Used in cases where Lua encounters an error and the user-defined error handling function also
        /// encounters an error. Functions like `pCall()`, which invoke a Lua function, may be configured
        /// to use an error-handling function when the call fails.
        ErrorHandlerFailure,
    } || CallError;

    /// Calls a function. To call a function, first push the function onto the stack, then push its arguments
    /// in direct order. `nargs` is the number of arguments pushed onto the stack. All arguments and the function
    /// value are popped from the stack when the function is called. The function results are pushed onto the
    /// stack when the function returns. The number of results is adjusted to `nresults`, unless `nresults` is
    /// `Lua.MultipleReturn`, in which case all results from the function are pushed.
    ///
    /// Lua takes care that the returned values fit into the stack space. The function results are pushed onto
    /// the stack in direct order (the first result is pushed first), so that after the call the last result is
    /// on the top of the stack.
    ///
    /// Any error inside the called function is propagated upwards.
    ///
    /// From: `void lua_call(lua_State *L, int nargs, int nresults);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_call
    /// Stack Behavior: `[-(nargs + 1), +nresults, e]`
    pub fn call(lua: *Lua, nargs: i32, nresults: i32) void {
        assert(nargs >= 0);
        assert(nresults >= 0 or nresults == Lua.MultipleReturn);

        return c.lua_call(asState(lua), nargs, nresults);
    }

    /// Calls a function in protected mode. If there are no errors during the call, behaves exactly like lua_call.
    /// However, if there is any error, catches it, pushes a single value on the stack (the error message),
    /// and returns an error code. Always removes the function and its arguments from the stack.
    ///
    /// If `errfunc` is 0, the error message returned on the stack is exactly the original error message.
    /// Otherwise, `errfunc` is the stack index of an error handler function. In case of runtime errors,
    /// this function will be called with the error message and its return value will be the message returned
    /// on the stack. Typically used to add more debug information to the error message.
    ///
    /// Returns 0 on success or one of the following error codes:
    /// - LUA_ERRRUN: runtime error
    /// - LUA_ERRMEM: memory allocation error
    /// - LUA_ERRERR: error while running the error handler function
    ///
    /// From: `int lua_pcall(lua_State *L, int nargs, int nresults, int errfunc);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_pcall
    /// Stack Behavior: `[-(nargs + 1), +(nresults|1), -]`
    pub fn protectedCall(lua: *Lua, nargs: i32, nresults: i32, errfunc: i32) ProtectedCallError!void {
        assert(nargs >= 0);
        assert(nresults >= 0 or nresults == Lua.MultipleReturn);

        const res = c.lua_pcall(asState(lua), nargs, nresults, errfunc);
        const status: LuaStatus = @enumFromInt(res);
        return switch (status) {
            .OK => return,
            .ERRRUN => error.Runtime,
            .ERRMEM => error.OutOfMemory,
            .ERRERR => error.ErrorHandlerFailure,
            else => std.debug.panic("Lua returned unexpected status code from protected call: {d}\n", .{res}),
        };
    }

    /// Opens all standard Lua libraries into the given state. Callers may prefer to open individual
    /// libraries instead, depending on their needs:
    /// * `openBaseLib`
    /// * `openPackageLib`
    /// * `openStringLib`
    /// * `openTableLib`
    /// * `openMathLib`
    /// * `openIOLib`
    /// * `openOSLib`
    /// * `openDebugLib`
    /// * etc.
    ///
    /// From: `void luaL_openlibs(lua_State *L);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_openlibs
    /// Stack Behavior: `[-0, +0, m]`
    pub fn openLibs(lua: *Lua) void {
        return c.luaL_openlibs(asState(lua));
    }

    /// Opens the standard library basic module, which includes the coroutine sub-library.
    ///
    /// (zig-luajit extension method)
    /// From: `int luaopen_base(lua_State *L);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#5
    /// Stack Behavior: `[-0, +0, m]`
    pub fn openBaseLib(lua: *Lua) void {
        c.lua_pushcclosure(asState(lua), c.luaopen_base, 0);
        lua.call(0, 0);
    }

    /// Opens the standard library math module, which contains functions like `sin`, `log` etc.
    ///
    /// (zig-luajit extension method)
    /// From: `int luaopen_math(lua_State *L);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#5
    /// Stack Behavior: `[-0, +0, m]`
    pub fn openMathLib(lua: *Lua) void {
        c.lua_pushcclosure(asState(lua), c.luaopen_math, 0);
        lua.call(0, 0);
    }

    /// Opens the standard library string manipulation module, which contains functions like `format`.
    ///
    /// (zig-luajit extension method)
    /// From: `int luaopen_string(lua_State *L);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#5
    /// Stack Behavior: `[-0, +0, m]`
    pub fn openStringLib(lua: *Lua) void {
        c.lua_pushcclosure(asState(lua), c.luaopen_string, 0);
        lua.call(0, 0);
    }

    /// Opens the standard library table manipulation module.
    ///
    /// (zig-luajit extension method)
    /// From: `int luaopen_table(lua_State *L);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#5
    /// Stack Behavior: `[-0, +0, m]`
    pub fn openTableLib(lua: *Lua) void {
        c.lua_pushcclosure(asState(lua), c.luaopen_table, 0);
        lua.call(0, 0);
    }

    /// Opens the standard library input and output module, containing functions to access the file
    /// system and network.
    ///
    /// (zig-luajit extension method)
    /// From: `int luaopen_io(lua_State *L);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#5
    /// Stack Behavior: `[-0, +0, m]`
    pub fn openIOLib(lua: *Lua) void {
        c.lua_pushcclosure(asState(lua), c.luaopen_io, 0);
        lua.call(0, 0);
    }

    /// Opens the standard library operating system facilities module.
    ///
    /// (zig-luajit extension method)
    /// From: `int luaopen_os(lua_State *L);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#5
    /// Stack Behavior: `[-0, +0, m]`
    pub fn openOSLib(lua: *Lua) void {
        c.lua_pushcclosure(asState(lua), c.luaopen_os, 0);
        lua.call(0, 0);
    }

    /// Opens the standard library package library.
    ///
    /// (zig-luajit extension method)
    /// From: `int luaopen_package(lua_State *L);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#5
    /// Stack Behavior: `[-0, +0, m]`
    pub fn openPackageLib(lua: *Lua) void {
        c.lua_pushcclosure(asState(lua), c.luaopen_package, 0);
        lua.call(0, 0);
    }

    /// Opens the standard library debug facilities module.
    ///
    /// (zig-luajit extension method)
    /// From: `int luaopen_debug(lua_State *L);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#5
    /// Stack Behavior: `[-0, +0, m]`
    pub fn openDebugLib(lua: *Lua) void {
        c.lua_pushcclosure(asState(lua), c.luaopen_debug, 0);
        lua.call(0, 0);
    }

    /// Opens the standard library (LuaJIT) bit manipulation module.
    ///
    /// (zig-luajit extension method)
    /// From: `int luaopen_bit(lua_State *L);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#5
    /// Stack Behavior: `[-0, +0, m]`
    pub fn openBitLib(lua: *Lua) void {
        c.lua_pushcclosure(asState(lua), c.luaopen_bit, 0);
        lua.call(0, 0);
    }

    /// Opens the standard library (LuaJIT) Just-In-Time compiler control module.
    ///
    /// (zig-luajit extension method)
    /// From: `int luaopen_jit(lua_State *L);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#5
    /// Stack Behavior: `[-0, +0, m]`
    pub fn openJITLib(lua: *Lua) void {
        c.lua_pushcclosure(asState(lua), c.luaopen_jit, 0);
        lua.call(0, 0);
    }

    /// Opens the standard library (LuaJIT) foreign function interface manipulation module, which contains
    /// functions calling external C functions and the use of C data structures from pure Lua code.
    ///
    /// (zig-luajit extension method)
    /// From: `int luaopen_ffi(lua_State *L);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#5
    /// Stack Behavior: `[-0, +0, m]`
    pub fn openFFILib(lua: *Lua) void {
        c.lua_pushcclosure(asState(lua), c.luaopen_ffi, 0);
        lua.call(0, 0);
    }

    /// Opens the standard library (LuaJIT) string buffer library, which contains functions for performing
    /// high-performance manipulation of string-like data. Unlike Lua strings, which are constants, string
    /// buffers are mutable sequences of 8-bit (binary-transparent) characters. Data can be stored,
    /// formatted and encoded into a string buffer and later converted, extracted or decoded.
    ///
    /// (zig-luajit extension method)
    /// From: `int luaopen_string_buffer(lua_State *L);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#5
    /// Stack Behavior: `[-0, +0, m]`
    pub fn openStringBufferLib(lua: *Lua) void {
        c.lua_pushcclosure(asState(lua), c.luaopen_string_buffer, 0);
        lua.call(0, 0);
    }

    pub const DoStringError = error{
        InvalidSyntax,
    } || ProtectedCallError;

    /// Loads the Lua chunk in the given string and, if there are no errors, pushes the compiled chunk as a
    /// Lua function on top of the stack before executing it using `protectedCall()`. Essentially, `doString()`
    /// executes the provided zero-terminated Lua code.
    ///
    /// From: `int luaL_dostring(lua_State *L, const char *str);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_dostring
    /// Stack Behavior: `[-0, +?, m]`
    pub fn doString(lua: *Lua, str: [*:0]const u8) DoStringError!void {
        const res = c.luaL_loadstring(asState(lua), str);
        const status: Lua.LuaStatus = @enumFromInt(res);
        switch (status) {
            .ERRSYNTAX => return error.InvalidSyntax,
            .ERRMEM => return error.OutOfMemory,
            else => {
                assert(res == 0); // luaL_loadstring returned an error code outside of the documented values.
            },
        }

        return lua.protectedCall(0, Lua.MultipleReturn, 0);
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

    try std.testing.expect(lua.typeOf(1) == Lua.Type.none);
    try std.testing.expect(lua.isNone(1));
    try std.testing.expect(lua.isNoneOrNil(1));
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
    try std.testing.expect(lua.typeOf(1) == Lua.Type.nil);
    try std.testing.expect(lua.isNil(1));
    try std.testing.expect(lua.isNoneOrNil(1));
    try std.testing.expect(!(lua.typeOf(1) == Lua.Type.none));
    try std.testing.expect(!lua.isNone(1));
    lua.pop(1);

    lua.pushBoolean(true);
    try std.testing.expect(lua.typeOf(1) == Lua.Type.boolean);
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
    try std.testing.expect(lua.typeOf(1) == Lua.Type.number);
    try std.testing.expect(lua.isInteger(1));
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
    try std.testing.expect(lua.typeOf(1) == Lua.Type.number);
    try std.testing.expect(lua.isNumber(1));
    try std.testing.expect(lua.isString(1));
    try std.testing.expect(!lua.isInteger(1));
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

    lua.newTable();
    try std.testing.expect(lua.isTable(1));
    try std.testing.expectEqual(Lua.Type.table, lua.typeOf(1));
    lua.pop(1);

    lua.createTable(1, 0);
    try std.testing.expect(lua.isTable(1));
    try std.testing.expectEqual(Lua.Type.table, lua.typeOf(1));
    lua.pop(1);

    try std.testing.expectEqualSlices(u8, "no value", lua.typeName(Lua.Type.none));
    try std.testing.expectEqualSlices(u8, "nil", lua.typeName(Lua.Type.nil));
    try std.testing.expectEqualSlices(u8, "boolean", lua.typeName(Lua.Type.boolean));
    try std.testing.expectEqualSlices(u8, "userdata", lua.typeName(Lua.Type.userdata));
    try std.testing.expectEqualSlices(u8, "number", lua.typeName(Lua.Type.number));
    try std.testing.expectEqualSlices(u8, "string", lua.typeName(Lua.Type.string));
    try std.testing.expectEqualSlices(u8, "table", lua.typeName(Lua.Type.table));
    try std.testing.expectEqualSlices(u8, "function", lua.typeName(Lua.Type.function));
    try std.testing.expectEqualSlices(u8, "userdata", lua.typeName(Lua.Type.light_userdata));
    try std.testing.expectEqualSlices(u8, "thread", lua.typeName(Lua.Type.thread));
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

test "toInteger and toIntegerStrict" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    try std.testing.expectError(error.NoneIsNotNumber, lua.toIntegerStrict(1));

    lua.pushInteger(10);
    try std.testing.expectEqual(10, lua.toInteger(1));
    try std.testing.expectEqual(10, try lua.toIntegerStrict(1));
    lua.pop(1);

    lua.pushNumber(10.2);
    try std.testing.expectEqual(10, lua.toInteger(1));
    try std.testing.expectEqual(10, try lua.toIntegerStrict(1));
    lua.pop(1);

    lua.pushString("45");
    try std.testing.expectEqual(45, lua.toInteger(1));
    try std.testing.expectError(error.StringIsNotNumber, lua.toIntegerStrict(1));
    lua.pop(1);

    lua.pushBoolean(false);
    try std.testing.expectEqual(0, lua.toInteger(1));
    try std.testing.expectError(error.BooleanIsNotNumber, lua.toIntegerStrict(1));
    lua.pop(1);

    lua.pushNil();
    try std.testing.expectEqual(0, lua.toInteger(1));
    try std.testing.expectError(error.NilIsNotNumber, lua.toIntegerStrict(1));
    lua.pop(1);
}

test "toNumber and toNumberStrict" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    try std.testing.expectError(error.NoneIsNotNumber, lua.toNumberStrict(1));

    lua.pushInteger(10);
    try std.testing.expectEqual(10.0, lua.toNumber(1));
    try std.testing.expectEqual(10.0, try lua.toNumberStrict(1));
    lua.pop(1);

    lua.pushNumber(10.2);
    try std.testing.expectEqual(10.2, lua.toNumber(1));
    try std.testing.expectEqual(10.2, try lua.toNumberStrict(1));
    lua.pop(1);

    lua.pushString("45");
    try std.testing.expectEqual(45.0, lua.toNumber(1));
    try std.testing.expectError(error.StringIsNotNumber, lua.toNumberStrict(1));
    lua.pop(1);

    lua.pushString("45.54");
    try std.testing.expectEqual(45.54, lua.toNumber(1));
    try std.testing.expectError(error.StringIsNotNumber, lua.toNumberStrict(1));
    lua.pop(1);

    lua.pushBoolean(false);
    try std.testing.expectEqual(0, lua.toNumber(1));
    try std.testing.expectError(error.BooleanIsNotNumber, lua.toNumberStrict(1));
    lua.pop(1);

    lua.pushNil();
    try std.testing.expectEqual(0, lua.toNumber(1));
    try std.testing.expectError(error.NilIsNotNumber, lua.toNumberStrict(1));
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

test "toString errors" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    lua.pushNil();
    lua.pushBoolean(true);
    try std.testing.expectError(error.BooleanIsNotString, lua.toString(-1));
    try std.testing.expectError(error.BooleanIsNotString, lua.toLString(-1));
    lua.pop(1);
    try std.testing.expectError(error.NilIsNotString, lua.toLString(-1));
    try std.testing.expectError(error.NilIsNotString, lua.toLString(-1));
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

test "tables" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    lua.newTable();
    lua.pushInteger(1);
    lua.pushString("Hello, world!");
    try std.testing.expectEqual(3, lua.getTop());

    lua.setTable(-3);
    try std.testing.expectEqual(1, lua.getTop());

    lua.pushInteger(1);
    try std.testing.expectEqual(Lua.Type.string, lua.getTable(-2));
    lua.pop(1);
    lua.pushInteger(1);
    try std.testing.expectEqual(Lua.Type.string, lua.getTableRaw(-2));
}

test "lengthOf" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    lua.newTable();
    lua.pushInteger(1);
    lua.pushString("Hello, world!");
    lua.setTable(-3);
    lua.pushInteger(2);
    lua.pushString("Ayo");
    try std.testing.expectEqual(3, lua.lengthOf(-1));
    lua.setTable(-3);
    try std.testing.expectEqual(2, lua.lengthOf(-1));
    lua.pop(1);

    lua.pushInteger(257);
    try std.testing.expectEqual(3, lua.lengthOf(-1)); // Implicit conversion to string
    lua.pop(1);
    lua.pushNumber(145.125);
    try std.testing.expectEqual(7, lua.lengthOf(-1)); // Implicit conversion to string
    lua.pop(1);

    lua.pushNil();
    try std.testing.expectEqual(0, lua.lengthOf(-1));
    lua.pop(1);
}

fn dummyCFunction(lua: *Lua) callconv(.c) i32 {
    _ = lua;
    return 0;
}

fn dummyCClosure(lua: *Lua) callconv(.c) i32 {
    const n = lua.toNumber(lua.upvalueIndex(1));
    lua.pushNumber(n);
    return 1;
}

test "c functions and closures with call" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    lua.pushCFunction(dummyCFunction);
    try std.testing.expectEqual(1, lua.getTop());
    try std.testing.expect(lua.isCFunction(1) and lua.isCFunction(-1));
    try std.testing.expect(lua.isFunction(1) and lua.isFunction(-1));
    lua.call(0, 0);
    try std.testing.expectEqual(0, lua.getTop());

    const expected: i64 = 42;
    lua.pushInteger(expected);
    lua.pushCClosure(dummyCClosure, 1);
    try std.testing.expectEqual(1, lua.getTop());
    try std.testing.expect(lua.isCFunction(1) and lua.isCFunction(-1));
    try std.testing.expect(lua.isFunction(1) and lua.isFunction(-1));
    lua.call(0, 1);
    try std.testing.expectEqual(1, lua.getTop());
    const actual = lua.toInteger(-1);
    try std.testing.expectEqual(expected, actual);
    lua.pop(1);
}

test "c functions and closures with protectedCall" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    lua.pushCFunction(dummyCFunction);
    try std.testing.expectEqual(1, lua.getTop());
    try std.testing.expect(lua.isCFunction(1) and lua.isCFunction(-1));
    try std.testing.expect(lua.isFunction(1) and lua.isFunction(-1));
    try lua.protectedCall(0, 0, 0);
    try std.testing.expectEqual(0, lua.getTop());

    const expected: i64 = 42;
    lua.pushInteger(expected);
    lua.pushCClosure(dummyCClosure, 1);
    try std.testing.expectEqual(1, lua.getTop());
    try std.testing.expect(lua.isCFunction(1) and lua.isCFunction(-1));
    try std.testing.expect(lua.isFunction(1) and lua.isFunction(-1));
    try lua.protectedCall(0, 1, 0);
    try std.testing.expectEqual(1, lua.getTop());
    const actual = lua.toInteger(-1);
    try std.testing.expectEqual(expected, actual);
    lua.pop(1);
}

test "openLibs doesn't effect the stack" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    lua.openLibs();
    try std.testing.expectEqual(0, lua.getTop());
}

test "openLibs can be called multiple times" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    lua.openLibs();
    try std.testing.expectEqual(0, lua.getTop());
    lua.openLibs();
    try std.testing.expectEqual(0, lua.getTop());
}

test "openBaseLib can be called multiple times after openlibs" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    lua.openLibs();
    try std.testing.expectEqual(0, lua.getTop());
    lua.openBaseLib();
    try std.testing.expectEqual(0, lua.getTop());
    lua.openBaseLib();
    try std.testing.expectEqual(0, lua.getTop());

    const expected = 42;
    lua.pushInteger(expected);
    const actual = lua.toInteger(-1);
    try std.testing.expectEqual(expected, actual);
}

test "openLibs individually" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    lua.openBaseLib();
    lua.openMathLib();
    lua.openStringLib();
    lua.openTableLib();
    lua.openIOLib();
    lua.openOSLib();
    lua.openPackageLib();
    lua.openDebugLib();
    lua.openBitLib();
    lua.openJITLib();
    lua.openFFILib();
    lua.openStringBufferLib();
}

test "traversal over table with next" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    lua.newTable();
    lua.pushNil();
    try std.testing.expect(!lua.next(-2));
    try std.testing.expectEqual(1, lua.getTop());

    lua.pushInteger(1);
    lua.pushString("Hello, world!");
    lua.setTable(-3);

    lua.pushInteger(2);
    lua.pushString("Hello back.");
    lua.setTable(-3);
    try std.testing.expectEqual(1, lua.getTop());

    lua.pushNil();
    try std.testing.expect(lua.next(-2));
    try std.testing.expect(lua.isString(-1));
    lua.pop(1);
    try std.testing.expect(lua.isInteger(-1));

    try std.testing.expect(lua.next(-2));
    try std.testing.expect(lua.isString(-1));
    lua.pop(1);
    try std.testing.expect(lua.isInteger(-1));

    try std.testing.expect(!lua.next(-2));
}

test "doString should do the string" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    try lua.doString(
        \\ local M = {}
        \\ return M
    );
    try std.testing.expect(lua.isTable(-1));
    lua.pop(1);

    try lua.doString(
        \\ return 42
    );
    try std.testing.expect(lua.isInteger(-1));
    lua.pop(1);

    try lua.doString(
        \\ return 42.42
    );
    try std.testing.expect(lua.isNumber(-1) and !lua.isInteger(-1));
    lua.pop(1);

    try lua.doString(
        \\ return "Hello, world!"
    );
    try std.testing.expect(lua.isString(-1));
    const actual = try lua.toLString(-1);
    try std.testing.expectEqualSlices(u8, "Hello, world!", actual);
    lua.pop(1);
}
