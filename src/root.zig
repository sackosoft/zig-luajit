//! Copyright (c) 2024-2025 Theodore Sackos
//! SPDX-License-Identifier: AGPL-3.0-or-later

const std = @import("std");
const assert = std.debug.assert;

const builtin = @import("builtin");
const isSafeBuildTarget: bool = builtin.mode == .ReleaseSafe or builtin.mode == .Debug;

const c = @import("c");
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
        const ud = try alloc.create(aa.AllocationUserdata);
        errdefer alloc.destroy(ud);
        ud.alloc = alloc;

        const lua: ?*Lua = @ptrCast(c.lua_newstate(aa.alloc, ud));
        return if (lua) |p| p else error.OutOfMemory;
    }

    fn asState(lua: *Lua) *c.lua_State {
        return @ptrCast(lua);
    }

    fn asCString(str: [:0]const u8) [*:0]const u8 {
        return @ptrCast(str.ptr);
    }

    fn asCFn(f: CFunction) ?*const fn (?*c.lua_State) callconv(.c) c_int {
        return @ptrCast(f);
    }

    /// Sets a new panic function and returns the old one. If an error happens outside any protected environment,
    /// Lua calls a panic function and then calls exit(EXIT_FAILURE), thus exiting the host application.
    /// Your panic function can avoid this exit by never returning (e.g., doing a long jump).
    /// The panic function can access the error message at the top of the stack.
    ///
    /// From: `lua_CFunction lua_atpanic(lua_State *L, lua_CFunction panicf);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_atpanic
    /// Stack Behavior: `[-0, +0, -]`
    pub fn atPanic(lua: *Lua, f: ?CFunction) ?CFunction {
        return @ptrCast(c.lua_atpanic(asState(lua), @ptrCast(f)));
    }

    /// Returns the Zig allocator currently being used by the lua instance.
    ///
    /// Note: This function has been renamed to represent the correct Zig idioms. Callers do not have control over
    /// the allocation function itself, they control the `std.mem.Allocator` instance that Lua uses.
    ///
    /// From: `lua_Alloc lua_getallocf(lua_State *L, void **ud);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_getallocf
    /// Stack Behavior: `[-0, +0, -]`
    pub fn getAllocator(lua: *Lua) std.mem.Allocator {
        const ud: *aa.AllocationUserdata = lua.getAllocationUserdata();
        return ud.alloc;
    }

    /// Changes the allocator used internally by the lua instance.
    ///
    /// Note: This function has been renamed to represent the correct Zig idioms. Callers do not have control over
    /// the allocation function itself, they control the `std.mem.Allocator` instance that Lua uses.
    ///
    /// From: `void lua_setallocf(lua_State *L, lua_Alloc f, void *ud);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_setallocf
    /// Stack Behavior: `[-0, +0, -]`
    pub fn setAllocator(lua: *Lua, alloc: std.mem.Allocator) void {
        var ud: *aa.AllocationUserdata = lua.getAllocationUserdata();
        ud.alloc = alloc;
    }

    fn getAllocationUserdata(lua: *Lua) *aa.AllocationUserdata {
        var ud: *aa.AllocationUserdata = undefined;
        const allocf = c.lua_getallocf(@ptrCast(lua), @ptrCast(&ud));

        // The Lua C API provides callers the ability to redefine both a function that performs memory allocation
        // AND a caller defined context ("userdata"); however, the idiomatic Zig memory allocation pattern is
        // captured by the `std.mem.Allocator` pattern.
        //
        // We've defined an adapater function which allows Lua to perform allocations within a `std.mem.Allocator`
        // instance, and as a result, we never want the allocation function inside the Lua instance to change.
        // My current expectation is that the allocation function changing indicates a defect being introduced.
        // Instead, all customizations to allocation behavior should be handled by passing in new `std.mem.Allocator`
        // instances. Whenever we touch that area of Lua, we are going to call this function in debug and safe builds
        // to check that the invariant holds true.
        assert(allocf != null);
        assert(allocf == aa.alloc); // Invariant Violated: The allocator function registered in lua has changed from the default. The author currently believes this function should never change under any circumstances.

        return ud;
    }

    /// Closes the Lua state and frees all resources.
    ///
    /// This includes:
    /// - All memory allocated by Lua
    /// - The heap-allocated copy of the caller-provided `std.mem.Allocator` instance
    ///   that was created in init()
    ///
    /// The Lua pointer is invalid after this call.
    ///
    /// From: `void lua_close(lua_State *L);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_close
    pub fn deinit(lua: *Lua) void {
        var ud: *aa.AllocationUserdata = lua.getAllocationUserdata();
        c.lua_close(@ptrCast(lua));
        ud.alloc.destroy(ud);
    }

    /// Ensures that there are at least `extra` free stack slots in the stack by allocating additional slots. Returns
    /// false if it cannot grow the stack to that size. This function never shrinks the stack; if the stack is already
    /// larger than the new size, it is left unchanged.
    ///
    /// From: `int lua_checkstack(lua_State *L, int extra);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_checkstack
    /// Stack Behavior: `[-0, +0, -]`
    pub fn checkStack(lua: *Lua, extra: i32) error{ OutOfMemory, StackOverflow }!void {
        const MaxStackSize: i32 = c.LUAI_MAXCSTACK;

        assert(extra >= 0);

        if (lua.getTop() + extra > MaxStackSize) {
            return error.StackOverflow;
        }
        if (0 == c.lua_checkstack(asState(lua), @intCast(extra))) {
            return error.OutOfMemory;
        }
    }

    /// Grows the stack size to have `extra` additional elements, raising an error if the stack cannot grow to that
    /// size. The `message` is an additional text to go into the error message.
    ///
    /// From: `void luaL_checkstack(lua_State *L, int sz, const char *msg);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_checkstack
    /// Stack Behavior: `[-0, +0, v]`
    pub fn checkStackOrError(lua: *Lua, extra: i32, message: [:0]const u8) void {
        assert(extra >= 0);

        return c.luaL_checkstack(asState(lua), extra, @ptrCast(message.ptr));
    }

    /// Returns the name of the type encoded by the value `t`.
    /// Caller *does not* own the returned slice.
    ///
    /// From: `const char *lua_typename(lua_State *L, int tp);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_typename
    /// Stack Behavior: `[-0, +0, -]`
    pub fn getTypeName(lua: *Lua, t: Lua.Type) [:0]const u8 {
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
        assert(index >= 0 and index < type_to_name.len);

        return type_to_name[@as(usize, @intCast(index))];
    }

    /// Returns the name of the type of the value at the given index.
    /// Caller *does not* own the returned slice.
    ///
    /// From: `const char *luaL_typename(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_typename
    /// Stack Behavior: `[-0, +0, -]`
    pub fn getTypeNameAt(lua: *Lua, index: i32) [:0]const u8 {
        lua.skipIndexValidation(
            index,
            "getType() safely returns `Lua.Type.none` when the index is not valid, and this has a valid name of 'no value'.",
        );

        const t = lua.getType(index);
        return lua.getTypeName(t);
    }

    /// Explicitly marks stack index usage as intentionally unchecked. Used when the Lua C API behavior
    /// is well-defined even for invalid indices, such as `getType()` returning `Lua.Type.None` when
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
        if (isSafeBuildTarget) {
            if (index <= PseudoIndex.Registry) {
                const max_upvalues_count = 255;
                assert(@as(i32, @intCast(PseudoIndex.Globals - max_upvalues_count)) <= index); // Safety check failed: pseudo-index exceeds maximum number of upvalues (255). This can also happen if your stack index has been corrupted and become a very large negative number.
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
    pub fn getType(lua: *Lua, index: i32) Lua.Type {
        lua.skipIndexValidation(
            index,
            "getType() safely returns `Lua.Type.none` when the index is not valid (required by Lua spec).",
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

        return lua.getType(index) == Lua.Type.none or lua.getType(index) == Lua.Type.nil;
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

        return lua.getType(index) == Lua.Type.none;
    }

    /// Returns true if the value at the given acceptable index is nil, and false otherwise.
    ///
    /// From: `int lua_isnil(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_isnil
    /// Stack Behavior: `[-0, +0, -]`
    pub fn isNil(lua: *Lua, index: i32) bool {
        lua.validateStackIndex(index);

        return lua.getType(index) == Lua.Type.nil;
    }

    /// Returns true if the value at the given acceptable index has type boolean, false otherwise.
    ///
    /// From: `int lua_isboolean(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_isboolean
    /// Stack Behavior: `[-0, +0, -]`
    pub fn isBoolean(lua: *Lua, index: i32) bool {
        lua.validateStackIndex(index);

        return lua.getType(index) == Lua.Type.boolean;
    }

    /// Returns true if the value at the given acceptable index is a function (either C or Lua), and false otherwise.
    ///
    /// From: `int lua_isfunction(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_isfunction
    /// Stack Behavior: `[-0, +0, -]`
    pub fn isFunction(lua: *Lua, index: i32) bool {
        lua.validateStackIndex(index);

        return lua.getType(index) == Lua.Type.function;
    }

    /// Returns true if the value at the given acceptable index is a light userdata, false otherwise.
    ///
    /// From: `int lua_islightuserdata(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_islightuserdata
    /// Stack Behavior: `[-0, +0, -]`
    pub fn isLightUserdata(lua: *Lua, index: i32) bool {
        lua.validateStackIndex(index);

        return lua.getType(index) == Lua.Type.light_userdata;
    }

    /// Returns true if the value at the given acceptable index is a table, false otherwise.
    ///
    /// From: `int lua_istable(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_istable
    /// Stack Behavior: `[-0, +0, -]`
    pub fn isTable(lua: *Lua, index: i32) bool {
        lua.validateStackIndex(index);

        return lua.getType(index) == Lua.Type.table;
    }

    /// Returns true if the value at the given acceptable index is a thread, and false otherwise.
    ///
    /// From: `int lua_isthread(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_isthread
    /// Stack Behavior: `[-0, +0, -]`
    pub fn isThread(lua: *Lua, index: i32) bool {
        lua.validateStackIndex(index);

        return lua.getType(index) == Lua.Type.thread;
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

        return switch (lua.getType(index)) {
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
    /// Callers may also use `getType()` or `isBoolean()` to check the value on the stack before evaluating its value.
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

        const t = lua.getType(index);
        if (t == Lua.Type.number) {
            return c.lua_tointeger(asState(lua), index);
        } else {
            return typeIsNotNumber(t);
        }
    }

    fn typeIsNotNumber(t: Lua.Type) NotNumberError {
        switch (t) {
            .number => unreachable,
            .string => return error.StringIsNotNumber,
            .none => return error.NoneIsNotNumber,
            .nil => return error.NilIsNotNumber,
            .boolean => return error.BooleanIsNotNumber,
            .light_userdata => return error.LightUserdataIsNotNumber,
            .table => return error.TableIsNotNumber,
            .function => return error.FunctionIsNotNumber,
            .userdata => return error.UserdataIsNotNumber,
            .thread => return error.ThreadIsNotNumber,
        }
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

        const t = lua.getType(index);
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

    /// Used for accessing special variables like the C registry, environment table and global tables.
    ///
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#3.3
    pub const PseudoIndex = struct {
        /// The registry table index. This is a special table that can be used by C/Zig code to store Lua values
        /// for later retrieval. Unlike the global table, the registry table is not accessible from Lua code.
        ///
        /// Lua provides a registry, a pre-defined table that can be used by any C code to store whatever Lua value
        /// it needs to store. This table is always located at `PseudoIndex.Registry`. Any C library can store
        /// data into this table, but it should take care to choose keys different from those used by other libraries, to
        /// avoid collisions. Typically, you should use as key a string containing your library name or a light userdata
        /// with the address of a C object in your code.
        ///
        /// The integer keys in the registry are used by the reference mechanism, implemented by the auxiliary
        /// library, and therefore should not be used for other purposes.
        ///
        /// Refer to: https://www.lua.org/manual/5.1/manual.html#3.5
        pub const Registry: i32 = c.LUA_REGISTRYINDEX;

        /// The environment table index for the current function. For Lua functions, this is the _ENV table
        /// where global variables are stored. For C/Zig functions, this is initially set to the global table.
        ///
        /// Refer to: https://www.lua.org/manual/5.1/manual.html#2.9
        /// Refer to: https://www.lua.org/manual/5.1/manual.html#3.5
        pub const Environment: i32 = c.LUA_ENVIRONINDEX;

        /// The globals table index. This table lives at a special index (not directly on the stack) and contains all
        /// global variables. This is the same table as the default environment for Lua code.
        ///
        /// Refer to: https://www.lua.org/manual/5.1/manual.html#2.9
        /// Refer to: https://www.lua.org/manual/5.1/manual.html#3.5
        pub const Globals: i32 = c.LUA_GLOBALSINDEX;

        /// Returns a pseudo-index that refers to the upvalue at position `index` in the current function.
        /// Upvalues are numbered from 1 upward. This is used when manipulating upvalues from C/Zig code.
        ///
        /// When a C function is created, it is possible to associate some values with it, thus creating a "closure"
        /// (see https://www.lua.org/manual/5.1/manual.html#lua_pushcclosure and https://www.lua.org/manual/5.1/manual.html#3.4).
        /// When this happens, the values are popped from the stack and managed by the Lua runtime. C functions may
        /// reference these "upvalues" by a pseudo-index returned by this function. These pseudo-indices are not
        /// references to the stack like other indices, instead, they are assocaited with the C function and managed
        /// by the Lua runtime.
        ///
        /// The first value associated with the function is at position `PseudoIndex.upvalue(1)`, the second at
        /// `PseudoIndex.upvalue(2)`, and so on. C closures support only 255 upvalues.
        ///
        /// Refer to: https://www.lua.org/manual/5.1/manual.html#3.4.3
        /// Refer to: https://www.lua.org/manual/5.1/manual.html#3.5
        pub fn upvalue(index: u8) i32 {
            return Globals - index;
        }
    };

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

    /// Converts a value at the given acceptable index to a C function. If the value at the given index is
    /// not a function then `null` will be returned instead.
    ///
    /// From: `lua_CFunction lua_tocfunction(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_tocfunction
    /// Stack Behavior: `[-0, +0, -]`
    pub fn toCFunction(lua: *Lua, index: i32) ?Lua.CFunction {
        lua.validateStackIndex(index);

        return @ptrCast(c.lua_tocfunction(asState(lua), index));
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

    /// Allocates a new block of memory with the given size, pushes onto the stack a new full userdata containing the
    /// address of the allocated block, and returns this address. The type `Userdata` is provided to allow arbitrary
    /// native application data to be stored in Lua variables. This type corresponds to a block of raw memory and has
    /// no pre-defined operations in Lua, except assignment and identity test.
    ///
    /// Using metatables, callers may define operations for userdata values (see https://www.lua.org/manual/5.1/manual.html#2.8).
    /// Userdata values cannot be created or modified in Lua, only through this native API. This guarantees the integrity of data
    /// owned by the native application.
    ///
    /// When Lua collects a full userdata with a `gc` metamethod, Lua calls the metamethod and marks the userdata as
    /// finalized. When this userdata is collected again then Lua frees its corresponding memory.
    ///
    /// From: `void *lua_newuserdata(lua_State *L, size_t size);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_newuserdata
    /// Stack Behavior: `[-0, +1, m]`
    pub fn newUserdata(lua: *Lua, size: usize) *anyopaque {
        const addr: ?*anyopaque = @ptrCast(c.lua_newuserdata(asState(lua), size));

        // I read through the LuaJIT code and I can't see any way that a `NULL` gets returned. The only error
        // condition I can find is memory alloction failure -- but that will go through the panic route.
        // Until proven otherwise, we will assume the pointer is non-null and check this assumption in Debug and
        // ReleaseSafe builds.
        assert(addr != null);
        return addr.?;
    }

    /// Pushes a light userdata onto the stack. Userdata represent C values in Lua. A light userdata
    /// represents a pointer. It is a value (like a number): you do not create it, it has no individual
    /// metatable, and it is not collected (as it was never created). A light userdata is equal to "any"
    /// light userdata with the same C address.
    ///
    /// From: `void lua_pushlightuserdata(lua_State *L, void *p);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_pushlightuserdata
    /// Stack Behavior: `[-0, +1, -]`
    pub fn pushLightUserdata(lua: *Lua, p: ?*anyopaque) void {
        return c.lua_pushlightuserdata(asState(lua), p);
    }

    /// If the value at the given acceptable index is a full userdata, returns its block address.
    /// If the value is a light userdata, returns its pointer. Otherwise, returns `null`.
    ///
    /// From: `void *lua_touserdata(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_touserdata
    /// Stack Behavior: `[-0, +0, -]`
    pub fn toUserdata(lua: *Lua, index: i32) ?*anyopaque {
        lua.validateStackIndex(index);

        return @ptrCast(c.lua_touserdata(asState(lua), index));
    }

    /// Returns a pointer to the reference type Lua value at the specified stack index. If the
    /// type of the value at the specified index is not supported then `null` will be returned instead.
    ///
    /// Supported value types:
    ///    - userdata (both full and light)
    ///    - tables
    ///    - threads
    ///    - functions
    ///
    /// Some other behaviors that may not be obvious:
    ///    - The returned pointer is only valid while the corresponding Lua object is alive.
    ///    - Different objects will return different pointers.
    ///    - There is no API support for these pointers. They cannot be converted back to their original
    ///      Lua values, nor can they be used to update those values on the stack.
    ///
    /// The primary use case for this function is for debugging and object identity comparison.
    ///
    /// From: `const void *lua_topointer(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_topointer
    /// Stack Behavior: `[-0, +0, -]`
    pub fn toPointer(lua: *Lua, index: i32) ?*const anyopaque {
        lua.validateStackIndex(index);

        return @ptrCast(c.lua_topointer(asState(lua), index));
    }

    /// Pushes a copy of the element at the given valid index onto the stack.
    ///
    /// From: `void lua_pushvalue(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_pushvalue
    /// Stack Behavior: `[-0, +1, -]`
    pub fn pushValue(lua: *Lua, index: i32) void {
        lua.validateStackIndex(index);

        return c.lua_pushvalue(asState(lua), index);
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
            return typeIsNotString(lua.getType(index));
        }
    }

    /// Pushes the bytes in the given slice onto the stack as a string. Lua makes (or reuses) an internal copy of
    /// the given string, so the provided slice may freed or reused immediately after the function returns succesfully.
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
            return typeIsNotString(lua.getType(index));
        }
    }

    /// Pushes onto the stack a formatted string and returns a pointer to this string. Memory allocation is handled
    /// by Lua via garbage collection, callers do NOT own the returned slice.
    ///
    /// String format specifiers are restricted to the following options:
    /// * '%%' - Insert a literal '%' character in the string.
    /// * '%s' - Insert a zero-terminated string,
    /// * '%f' - Insert a `Lua.Number`, usually an `f64`,
    /// * '%p' - Insert a pointer-width ineger formatted as hexadecimal,
    /// * '%d' - Insert a `Lua.Integer`, usually an `i64`, and
    /// * '%c' - Insert a single character represented by a number.
    ///
    /// See also: `raiseErrorFormat()`
    /// From: `const char *lua_pushfstring(lua_State *L, const char *fmt, ...);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_pushfstring
    /// Stack Behavior: `[-0, +1, m]`
    pub fn pushFString(lua: *Lua, comptime format: [:0]const u8, args: anytype) [:0]const u8 {
        const string: ?[*:0]const u8 = @call(.auto, c.lua_pushfstring, .{ asState(lua), format.ptr } ++ args);
        if (string) |s| {
            // NOTE: This seems dangerous. I don't really like this solution, but it doesn't look like there is any other option.
            // We are making a strong assumption that Lua returns a well-behaved zero-terminated string.
            const len = std.mem.indexOfSentinel(u8, 0, s);
            return s[0..len :0];
        } else {
            std.debug.panic("Received unexpected NULL response from lua.pushFString(\"{s}, ...\")", .{format});
        }
    }

    fn typeIsNotString(t: Lua.Type) NotStringError {
        switch (t) {
            .number, .string => unreachable,

            .none => return error.NoneIsNotString,
            .nil => return error.NilIsNotString,
            .boolean => return error.BooleanIsNotString,
            .light_userdata => return error.LightUserdataIsNotString,
            .table => return error.TableIsNotString,
            .function => return error.FunctionIsNotString,
            .userdata => return error.UserdataIsNotString,
            .thread => return error.ThreadIsNotString,
        }
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
        assert(lua.isTable(index));

        c.lua_gettable(asState(lua), index);
        return lua.getType(-1);
    }

    /// Similar to `getTable()`, but this implementation will not invoke any metamethods.
    ///
    /// Note: This function was renamed for consistency with the other table value access functions.
    ///
    /// From: `void lua_rawget(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_rawget
    /// Stack Behavior: `[-1, +1, -]`
    pub fn getTableRaw(lua: *Lua, index: i32) Lua.Type {
        lua.validateStackIndex(index);
        assert(lua.isTable(index));

        c.lua_rawget(asState(lua), index);
        return lua.getType(-1);
    }

    /// Pushes onto the stack the value `t[n]`, where `t` is the value at the given valid index.
    /// The access is raw; that is, it does not invoke metamethods.
    ///
    /// Note: This function was renamed for consistency with the other table updating functions.
    ///
    /// From: `void lua_rawgeti(lua_State *L, int index, int n);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_rawgeti
    /// Stack Behavior: `[-0, +1, -]`
    pub fn getTableIndexRaw(lua: *Lua, index: i32, n: i32) Lua.Type {
        lua.validateStackIndex(index);
        assert(lua.isTable(index));

        c.lua_rawgeti(asState(lua), index, n);
        return lua.getType(-1);
    }

    pub const Ref = struct {
        pub const None: i32 = c.LUA_NOREF;
        pub const Nil: i32 = c.LUA_REFNIL;
    };

    /// Creates and returns a reference in the table at the specified index for the object at the top of the stack,
    /// then pops that object. The reference is a unique integer key that can be used to retrieve the object later.
    ///
    /// * You can retrieve the referenced object by calling `getTableIndexRaw()` with the returned reference as the key
    /// * The function `unref()` frees a reference and its associated object
    /// * If the object at the top of the stack is `nil` then `ref()` returns the constant `Lua.Ref.Nil`
    ///
    /// The constant `Lua.Ref.None` is guaranteed to be different from any reference returned by `ref()`.
    ///
    /// This function is typically used to store Lua values that need to persist between C/Zig function calls,
    /// often using `Lua.PseudoIndex.Registry` as the table index.
    ///
    /// From: `int luaL_ref(lua_State *L, int t);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_ref
    /// Stack Behavior: `[-1, +0, m]`
    pub fn ref(lua: *Lua, index: i32) i32 {
        lua.validateStackIndex(index);

        return c.luaL_ref(asState(lua), index);
    }

    /// Releases a reference from the table at the specified index. The entry is removed from the table, allowing the
    /// referred object to be collected. The reference is freed to be used again.
    ///
    /// If the reference is `Lua.Ref.None` or `Lua.Ref.Nil`, this function does nothing.
    ///
    /// From: `void luaL_unref(lua_State *L, int t, int ref);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_unref
    /// Stack Behavior: `[-0, +0, -]`
    pub fn unref(lua: *Lua, index: i32, reference: i32) void {
        lua.validateStackIndex(index);

        return c.luaL_unref(asState(lua), index, reference);
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

    /// Similar to `setTable()`, but does a raw assignment (i.e., without metamethods).
    ///
    /// Note: This function was renamed for consistency with the other table updating functions.
    ///
    /// From: `void lua_rawset(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_rawset
    /// Stack Behavior: `[-2, +0, m]`
    pub fn setTableRaw(lua: *Lua, index: i32) void {
        lua.validateStackIndex(index);
        assert(lua.isTable(index));

        return c.lua_rawset(asState(lua), index);
    }

    /// Does the equivalent of `t[n] = v`, where `t` is the value at the given valid index and `v` is the value
    /// at the top of the stack. The assignment is raw; that is, it does not invoke metamethods.
    ///
    /// Note: This function was renamed for consistency with the other table updating functions.
    ///
    /// From: `void lua_rawseti(lua_State *L, int index, int n);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_rawseti
    /// Stack Behavior: `[-1, +0, m]`
    pub fn setTableIndexRaw(lua: *Lua, index: i32, n: i32) void {
        lua.validateStackIndex(index);
        assert(lua.isTable(index));

        return c.lua_rawseti(asState(lua), index, n);
    }

    /// Pushes onto the stack the value `t[k]`, where `t` is the value at the given valid index. As in Lua, this function
    /// may trigger a metamethod for the "index" event (see https://www.lua.org/manual/5.1/manual.html#2.8).
    ///
    /// From: `void lua_getfield(lua_State *L, int index, const char *k);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_getfield
    /// Stack Behavior: `[-0, +1, e]`
    pub fn getField(lua: *Lua, index: i32, key: [:0]const u8) Lua.Type {
        lua.validateStackIndex(index);
        assert(lua.isTable(index));

        c.lua_getfield(asState(lua), index, @ptrCast(key.ptr));
        return lua.getType(-1);
    }

    /// Does the equivalent to `t[key] = v`, where `t` is the value at the given valid index and `v` is the value at the
    /// top of the stack. This function pops the value from the stack. As in Lua, this function may trigger a
    /// metamethod for the "newindex" event (see https://www.lua.org/manual/5.1/manual.html#2.8).
    ///
    /// From: `void lua_setfield(lua_State *L, int index, const char *k);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_setfield
    /// Stack Behavior: `[-1, +0, e]`
    pub fn setField(lua: *Lua, index: i32, key: [:0]const u8) void {
        lua.validateStackIndex(index);
        assert(lua.isTable(index));

        return c.lua_setfield(asState(lua), index, @ptrCast(key.ptr));
    }

    /// Pushes onto the stack the value of the global name.
    ///
    /// From: `void lua_getglobal(lua_State *L, const char *name);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_getglobal
    /// Stack Behavior: `[-0, +1, e]`
    pub fn getGlobal(lua: *Lua, name: [:0]const u8) Lua.Type {
        c.lua_getglobal(asState(lua), asCString(name));
        return lua.getType(-1);
    }

    /// Pops a value from the stack and sets it as the new value of global `name`.
    ///
    /// From: `void lua_setglobal(lua_State *L, const char *name);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_setglobal
    /// Stack Behavior: `[-1, +0, e]`
    pub fn setGlobal(lua: *Lua, name: [:0]const u8) void {
        assert(lua.getTop() > 0);

        return c.lua_setglobal(asState(lua), asCString(name));
    }

    /// Creates a new table to be used as a metatable for userdata, adds it to the registry with key `tname`, and
    /// returns `true`. If the registry already has the key `tname`, returns `false` instead.
    ///
    /// In both cases, pushes onto the stack the final value associated with `tname` in the registry.
    ///
    /// From: `int luaL_newmetatable(lua_State *L, const char *tname);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_newmetatable
    /// Stack Behavior: `[-0, +1, m]`
    pub fn newMetatable(lua: *Lua, tname: [:0]const u8) bool {
        return 1 == c.luaL_newmetatable(asState(lua), tname.ptr);
    }

    /// Pops a table from the top of the stack and sets it as the metatable for the value at the
    /// given acceptable index.
    ///
    /// From: `int lua_setmetatable(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_setmetatable
    /// Stack Behavior: `[-1, +0, -]`
    pub fn setMetatable(lua: *Lua, index: i32) void {
        lua.validateStackIndex(index);
        assert(lua.isTable(-1));

        const res = c.lua_setmetatable(asState(lua), index);
        assert(1 == res);
    }

    /// Pushes onto the stack the metatable of the value at the given acceptable index. If the index is not
    /// valid, or if the value does not have a metatable, the function returns `false` and pushes nothing on
    /// the stack.
    ///
    /// From: `int lua_getmetatable(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_getmetatable
    /// Stack Behavior: `[-0, +(0|1), -]`
    pub fn getMetatable(lua: *Lua, index: i32) bool {
        lua.validateStackIndex(index);

        return 1 == c.lua_getmetatable(asState(lua), index);
    }

    /// Pushes onto the stack the metatable associated with name `name` in the registry.
    ///
    /// Useful in combination with `newMetatable()`.
    ///
    /// From: `void luaL_getmetatable(lua_State *L, const char *tname);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_getmetatable
    /// Stack Behavior: `[-0, +1, -]`
    pub fn getMetatableRegistry(lua: *Lua, name: [:0]const u8) void {
        return c.luaL_getmetatable(asState(lua), name.ptr);
    }

    /// Pushes onto the stack the field `field_name` from the metatable of the object at index `index`. Returns `true`
    /// when the metatable exists and the requested field has been pushed on the stack. Otherwise, if the object does
    /// not have a metatable, or if the metatable does not have this field, returns `false` and pushes nothing.
    ///
    /// From: `int luaL_getmetafield(lua_State *L, int obj, const char *e);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_getmetafield
    /// Stack Behavior: `[-0, +(0|1), m]`
    pub fn getMetaField(lua: *Lua, index: i32, field_name: [:0]const u8) bool {
        lua.validateStackIndex(index);

        return 1 == c.luaL_getmetafield(asState(lua), index, field_name.ptr);
    }

    /// Calls a metamethod. If the object at the given index, `index` has a metatable and this metatable has a
    /// field `e`, this function calls this field and passes the object as its only argument. If the
    /// metamethod exists, it returns true and pushes the returned value onto the stack. If no
    /// metatable or metamethod exists, it returns false without pushing any value.
    ///
    /// From: `int luaL_callmeta(lua_State *L, int obj, const char *e);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_callmeta
    /// Stack Behavior: `[-0, +(0|1), e]`
    pub fn callMeta(lua: *Lua, index: i32, e: [:0]const u8) bool {
        lua.validateStackIndex(index);

        return 1 == c.luaL_callmeta(asState(lua), index, e.ptr);
    }

    /// Creates a new execution context within the given Lua instance, pushes it on the stack, and returns a `*Lua` pointer
    /// that represents this new thread. Do not confuse Lua threads with operating-system threads. Lua supports coroutines
    /// on all systems, even those that do not support threads.
    ///
    /// The created thread:
    /// * represents an independent thread of execution and is used to implement coroutines.
    /// * is not an operating system thread.
    /// * shares the enviornment of the creating thread.
    ///
    /// For information on Lua threads, refer to
    /// * [Lua Manual 2.2 - Values and Types](https://www.lua.org/manual/5.1/manual.html#2.2)
    /// * [Lua Manual 2.9 - Environments](https://www.lua.org/manual/5.1/manual.html#2.9)
    /// * [Lua Manual 2.11 - Coroutines](https://www.lua.org/manual/5.1/manual.html#2.11)
    ///
    /// Threads are subject to garbage collection, like any other Lua value. There is no function to close or destroy a
    /// thread. To dispose, pop the thread from the stack and it will eventually be collected.
    ///
    /// From: `lua_State *lua_newthread(lua_State *L);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_newthread
    /// Stack Behavior: `[-0, +1, m]`
    pub fn newThread(lua: *Lua) *Lua {
        const thread: ?*Lua = @ptrCast(c.lua_newthread(asState(lua)));

        // I read through the LuaJIT code and I can't see any way that a `NULL` gets returned. The only error
        // condition I can find is memory alloction failure -- but that will go through the panic route.
        // Until proven otherwise, we will assume the pointer is non-null and check this assumption in Debug and ReleaseSafe builds.
        assert(thread != null);
        assert(lua != thread.?);
        return thread.?;
    }

    /// Pushes the current Lua thread onto the stack and returns `true` if it's the main thread.
    ///
    /// The primary use cases for this function is:
    /// - to store thread references in Lua tables/registry for later retrieval from C code
    /// - to identify if code is running in main thread vs coroutine
    ///
    /// From: `int lua_pushthread(lua_State *L);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_pushthread
    /// Stack Behavior: `[-0, +1, -]`
    pub fn pushThread(lua: *Lua) bool {
        return 1 == c.lua_pushthread(asState(lua));
    }

    /// Converts the value at the given acceptable index to a Lua thread. This value must be a thread;
    /// otherwise, the function returns null.
    ///
    /// From: `lua_State *lua_tothread(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_tothread
    /// Stack Behavior: `[-0, +0, -]`
    pub fn toThread(lua: *Lua, index: i32) ?*Lua {
        lua.validateStackIndex(index);

        return @ptrCast(c.lua_tothread(asState(lua), index));
    }

    /// Pops `n` elements from the stack.
    ///
    /// From: `void lua_pop(lua_State *L, int n);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_pop
    /// Stack Behavior: `[-n, +0, -]`
    pub fn pop(lua: *Lua, n: i32) void {
        assert(n >= 0);
        assert(n <= lua.getTop());

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

    /// Accepts any acceptable index, or 0, and sets the stack top to this index. If the new top is
    /// larger than the old one, then the new elements are filled with nil. If index is 0, then all
    /// stack elements are removed.
    ///
    /// From: `void lua_settop(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_settop
    /// Stack Behavior: `[-?, +?, -]`
    pub fn setTop(lua: *Lua, index: i32) void {
        assert(index >= 0);

        return c.lua_settop(asState(lua), index);
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

    /// Removes the element at the given valid index, shifting down the elements above this index to fill the gap.
    /// Cannot be called with a pseudo-index, because a pseudo-index is not an actual stack position.
    ///
    /// From: `void lua_remove(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_remove
    /// Stack Behavior: `[-1, +0, -]`
    pub fn remove(lua: *Lua, index: i32) void {
        lua.validateStackIndex(index);

        return c.lua_remove(asState(lua), index);
    }

    /// Moves the top element into the given position (and pops it), without shifting any element
    /// (therefore replacing the value at the given position).
    ///
    /// From: `void lua_replace(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_replace
    /// Stack Behavior: `[-1, +0, -]`
    pub fn replace(lua: *Lua, index: i32) void {
        lua.validateStackIndex(index);

        return c.lua_replace(asState(lua), index);
    }

    /// Returns whether the two values in given acceptable indices are equal, following the semantics of the Lua `==`
    /// operator, which may call metamethods.
    ///
    /// In Debug or ReleaseSafe builds, the indicides are validated to be acceptable indices. In unsafe
    /// builds, the function will returns false if any of the indices is not valid.
    ///
    /// From: `int lua_equal(lua_State *L, int index1, int index2);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_equal
    /// Stack Behavior: `[-0, +0, e]`
    pub fn equal(lua: *Lua, index_left: i32, index_right: i32) bool {
        lua.validateStackIndex(index_left);
        lua.validateStackIndex(index_right);

        return 1 == c.lua_equal(asState(lua), index_left, index_right);
    }

    /// Returns whether the two values in given acceptable indices are equal, without the use of any metamethods.
    ///
    /// Note: This function was renamed from `rawEqual` for clarity and discoverability.
    ///
    /// From: `int lua_rawequal(lua_State *L, int index1, int index2);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_rawequal
    /// Stack Behavior: `[-0, +0, -]`
    pub fn equalRaw(lua: *Lua, index_left: i32, index_right: i32) bool {
        lua.validateStackIndex(index_left);
        lua.validateStackIndex(index_right);

        return 1 == c.lua_rawequal(asState(lua), index_left, index_right);
    }

    /// Returns whether the value at acceptable index `index_left` is smaller than the value at acceptable
    /// index `index_right`, following the semantics of the Lua < operator (that is, may call metamethods).
    ///
    /// In Debug or ReleaseSafe builds, the indicides are validated to be acceptable indices. In unsafe
    /// builds, the function will returns false if any of the indices is not valid.
    ///
    /// From: `int lua_lessthan(lua_State *L, int index1, int index2);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_lessthan
    /// Stack Behavior: `[-0, +0, e]`
    pub fn lessThan(lua: *Lua, index_left: i32, index_right: i32) bool {
        lua.validateStackIndex(index_left);
        lua.validateStackIndex(index_right);

        return 1 == c.lua_lessthan(asState(lua), index_left, index_right);
    }

    /// Concatenates the n values at the top of the stack, pops them, and leaves the result at the top.
    /// If n is 1, the result is the single value on the stack (that is, the function does nothing);
    /// if n is 0, the result is the empty string. Concatenation is performed following the usual
    /// semantics of the lua concat `..` operator (see https://www.lua.org/manual/5.1/manual.html#2.5.4).
    ///
    /// In Debug or ReleaseSafe builds, the values to be concatenated are checked to be strings, numbers
    /// or types with the `__concat` metamethod defined.
    ///
    /// From: `void lua_concat(lua_State *L, int n);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_concat
    /// Stack Behavior: `[-n, +1, e]`
    pub fn concat(lua: *Lua, n: i32) void {
        assert(n >= 0);

        // TODO: I think it would make sense to check that the `n` arguments are all either strings, numbers, or
        // types for which a `__concat` metamethod have been defined. The checks for strings and numbers are easy,
        // but the semantics of concat require handling metamethods which are a bit harder to check.
        // https://www.lua.org/manual/5.1/manual.html#2.8
        return c.lua_concat(asState(lua), n);
    }

    /// Returned by calls to the Lua VM to indicate the status of executing the request.
    pub const Status = enum(i32) {
        /// Indicates the last operation completed successfully with no errors. This is the normal
        /// return status for most Lua API functions.
        ok = c.LUA_OK,

        /// Coroutine has suspended execution via yield. Indicates normal coroutine suspension, not an
        /// error condition. The coroutine can be resumed later with `resumeCoroutine()`.
        yield = c.LUA_YIELD,

        /// Indicates that the last execution results in a Lua runtime error. This may indicate usage of
        /// undefined variables, dereference of `nil` or other runtime issues.
        /// from the stack.
        runtime_error = c.LUA_ERRRUN,

        /// Indicates that the Lua runtime failed to parse provided Lua source code before execution. This
        /// is likely a result of a mistake made by a user where the given code is malformed and incorrect.
        syntax_error = c.LUA_ERRSYNTAX,

        /// Indicates that Lua was unable to allocate memory required by the last operation.
        memory_error = c.LUA_ERRMEM,

        /// Indicates that an error occurred while running the error handler function such as after invoking
        /// a protected call.
        error_handling_error = c.LUA_ERRERR,

        /// Indicates that a file read operation failed, such as from `doFile()`.
        file_error = c.LUA_ERRFILE,

        fn is_status(s: i32) bool {
            return s == c.LUA_OK //
            or s == c.LUA_YIELD //
            or s == c.LUA_ERRRUN //
            or s == c.LUA_ERRSYNTAX //
            or s == c.LUA_ERRMEM //
            or s == c.LUA_ERRERR //
            or s == c.LUA_ERRFILE;
        }
    };

    /// Returns the current status of the thread. The status will be `Status.ok` for a normal thread, an error
    /// code if the thread finished its execution with an error, or `status.yield` if the thread is suspended.
    ///
    /// From: `int lua_status(lua_State *L);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_status
    /// Stack Behavior: `[-0, +0, -]`
    pub fn status(lua: *Lua) Status {
        const s: i32 = c.lua_status(asState(lua));
        assert(Status.is_status(s)); // Expected the status to be one of the "thread status" values defined in lua.h
        return @enumFromInt(s);
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
    pub fn getLength(lua: *Lua, index: i32) usize {
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
    ///     std.debug.print("The key is a '{s}'\n", .{lua.getTypeName(lua.getType(-2))});
    ///     std.debug.print("The value is a '{s}'\n", .{lua.getTypeName(lua.getType(-1))});
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

    /// Raises an error with the error message on the top of the stack. The error message may be a Lua value of any
    /// type, but usually a string is best. This function does a long jump and therefore never returns.
    ///
    /// From: `int lua_error(lua_State *L);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_error
    /// Stack Behavior: `[-1, +0, v]`
    pub fn raiseError(lua: *Lua) noreturn {
        _ = c.lua_error(asState(lua));
        unreachable;
    }

    /// Raises an error with the given error message format and optional arguments. The error message follows
    /// the same rules as `pushFString()` and includes the file name and line number where the error occurred,
    /// if such information is available. This function does a long jump and therefore never returns.
    ///
    /// In the given `format` string, format specifiers are restricted to the following options:
    /// * '%%' - Insert a literal '%' character in the string.
    /// * '%s' - Insert a zero-terminated string,
    /// * '%f' - Insert a `Lua.Number`, usually an `f64`,
    /// * '%p' - Insert a pointer-width ineger formatted as hexadecimal,
    /// * '%d' - Insert a `Lua.Integer`, usually an `i64`, and
    /// * '%c' - Insert a single character represented by a number.
    ///
    /// See also: `pushFString()`
    /// From: `int luaL_error(lua_State *L, const char *fmt, ...);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_error
    /// Stack Behavior: `[-0, +0, v]`
    pub fn raiseErrorFormat(lua: *Lua, format: [:0]const u8, args: anytype) noreturn {
        _ = @call(.auto, c.luaL_error, .{ asState(lua), format.ptr } ++ args);
        unreachable;
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

    /// Used as the value for `nresults` to return all results from the function on the stack when invoking
    /// `call()` or `callProtected()`.
    ///
    /// Usually, when using `call()` or `callProtected()`, the function results are pushed onto the stack when
    /// the function returns, then the number of results is adjusted to the value of `nresults` specified by the
    /// caller. By using `Lua.MultipleReturn`, all results from the function are left on the stack.
    pub const MultipleReturn: i32 = c.LUA_MULTRET;

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
    /// From: `int lua_pcall(lua_State *L, int nargs, int nresults, int errfunc);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_pcall
    /// Stack Behavior: `[-(nargs + 1), +(nresults|1), -]`
    pub fn callProtected(lua: *Lua, nargs: i32, nresults: i32, errfunc: i32) ProtectedCallError!void {
        assert(nargs >= 0);
        assert(nresults >= 0 or nresults == Lua.MultipleReturn);

        const res = c.lua_pcall(asState(lua), nargs, nresults, errfunc);
        assert(Status.is_status(res)); // Expected the status to be one of the "thread status" values defined in lua.h

        return parseCallStatus(res);
    }

    /// Calls the C function `func` in protected mode. `func` starts with only one element in its stack,
    /// a light userdata containing `ud`. In case of errors, returns the same error codes as `lua_pcall`,
    /// plus the error object on the top of the stack; otherwise, returns zero and does not change the stack.
    /// All values returned by `func` are discarded.
    ///
    /// From: `int lua_cpcall(lua_State *L, lua_CFunction func, void *ud);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_cpcall
    /// Stack Behavior: `[-0, +(0|1), -]`
    pub fn callProtectedC(lua: *Lua, f: CFunction, ud: ?*anyopaque) ProtectedCallError!void {
        const res = c.lua_cpcall(asState(lua), asCFn(f), ud);
        assert(Status.is_status(res)); // Expected the status to be one of the "thread status" values defined in lua.h

        return parseCallStatus(res);
    }

    fn parseCallStatus(res: c_int) ProtectedCallError!void {
        const s: Status = @enumFromInt(res);
        switch (s) {
            .ok => return,
            .runtime_error => return error.Runtime,
            .memory_error => return error.OutOfMemory,
            .error_handling_error => return error.ErrorHandlerFailure,
            else => std.debug.panic("Lua returned unexpected status code from a protected call: {d}\n", .{res}),
        }
    }

    /// Pops a table from the stack and sets it as the new environment for the value at the given index.
    /// Returns true if the value is a function, thread, or userdata, otherwise returns false. When a function or
    /// thread or userdata does a lookup for a name that is not found in the local context, this "fallback"
    /// table will be used instead.
    ///
    /// Note for readers familiar with Lua 5.2 or later: The Lua 5.1 `setfenv` was replaced by the standardized
    /// `_ENV` upvalue, since it makes environment handling more explicit. Unfortunately, LuaJIT is ABI compatible
    /// with Lua 5.1 meaning we must provide this older mechanism.
    ///
    /// See [Lua Manual 2.9 - Environments](https://www.lua.org/manual/5.1/manual.html#2.9)
    ///
    /// From: `int lua_setfenv(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_setfenv
    /// Stack Behavior: `[-1, +0, -]`
    pub fn setEnvironment(lua: *Lua, index: i32) bool {
        lua.validateStackIndex(index);
        assert(lua.isTable(-1));

        return 1 == c.lua_setfenv(asState(lua), index);
    }

    /// Pushes onto the stack the environment table of the value at the given index.
    ///
    /// Note for readers familiar with Lua 5.2 or later: The Lua 5.1 `getfenv` was replaced by the standardized
    /// `_ENV` upvalue, since it makes environment handling more explicit. Unfortunately, LuaJIT is ABI compatible
    /// with Lua 5.1 meaning we must provide this older mechanism.
    ///
    /// See [Lua Manual 2.9 - Environments](https://www.lua.org/manual/5.1/manual.html#2.9)
    ///
    /// From: `void lua_getfenv(lua_State *L, int index);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_getfenv
    /// Stack Behavior: `[-0, +1, -]`
    pub fn getEnvironment(lua: *Lua, index: i32) void {
        lua.validateStackIndex(index);

        return c.lua_getfenv(asState(lua), index);
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

    pub const LoadFileError = error{FileOpenOrFileRead} || LoadError;

    /// Loads a file as a Lua chunk. Uses `load()` internally to load the chunk in the file named filename.
    /// If filename is null, then it loads from the standard input. The first line in the file is ignored
    /// if it starts with a #. Returns the same results as lua_load, but with an extra error code LUA_ERRFILE
    /// if it cannot open/read the file. Only loads the chunk; it does not run it.
    ///
    /// From: `int luaL_loadfile(lua_State *L, const char *filename);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_loadfile
    /// Stack Behavior: `[-0, +1, m]`
    pub fn loadFile(lua: *Lua, filename: [:0]const u8) LoadFileError!void {
        const res = c.luaL_loadfile(asState(lua), filename);
        return interpretLoadFileRes(res, "loadFile()");
    }

    fn interpretLoadFileRes(res: c_int, source: []const u8) LoadFileError!void {
        assert(Status.is_status(res));
        const s: Lua.Status = @enumFromInt(res);
        switch (s) {
            .ok => return,
            .runtime_error => return error.Runtime,
            .syntax_error => return error.InvalidSyntax,
            .memory_error => return error.OutOfMemory,
            .file_error => return error.FileOpenOrFileRead,
            else => {
                std.debug.panic(
                    "Attempted load from '{s}' returned an unexpected error code '{d}'. Expected to be one of [ok({d}), runtime_error({d}), syntax_error({d}), memory_error({d}) or file_error({d})].\n",
                    .{
                        source,
                        res,
                        @intFromEnum(Lua.Status.ok),
                        @intFromEnum(Lua.Status.runtime_error),
                        @intFromEnum(Lua.Status.syntax_error),
                        @intFromEnum(Lua.Status.memory_error),
                        @intFromEnum(Lua.Status.file_error),
                    },
                );
            },
        }
    }

    /// Loads a buffer as a Lua chunk. The `name` parameter is used to identify the chunk and appears in error messages.
    ///
    /// From: `int luaL_loadbuffer(lua_State *L, const char *buff, size_t sz, const char *name);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_loadbuffer
    /// Stack Behavior: `[-0, +1, m]`
    pub fn loadBuffer(lua: *Lua, buffer: []const u8, name: [:0]const u8) LoadError!void {
        const res = c.luaL_loadbuffer(asState(lua), buffer.ptr, buffer.len, name.ptr);
        return interpretLoadRes(res, "loadBuffer()");
    }

    /// Loads a string as a Lua chunk using lua_load for the zero-terminated string.
    /// This function only loads the chunk and does not run it, returning the same results as lua_load.
    ///
    /// From: `int luaL_loadstring(lua_State *L, const char *s);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_loadstring
    /// Stack Behavior: `[-0, +1, m]`
    pub fn loadString(lua: *Lua, source: [:0]const u8) LoadError!void {
        const res = c.luaL_loadstring(asState(lua), source.ptr);
        return interpretLoadRes(res, "loadString()");
    }

    fn interpretLoadRes(res: c_int, source: []const u8) LoadError!void {
        assert(Status.is_status(res));
        const s: Lua.Status = @enumFromInt(res);
        switch (s) {
            .ok => return,
            .runtime_error => return error.Runtime,
            .syntax_error => return error.InvalidSyntax,
            .memory_error => return error.OutOfMemory,
            else => {
                std.debug.panic(
                    "Attempted load from '{s}' returned an unexpected error code '{d}'. Expected to be one of [ok({d}), runtime_error({d}), syntax_error({d}) or memory_error({d})].\n",
                    .{
                        source,
                        res,
                        @intFromEnum(Lua.Status.ok),
                        @intFromEnum(Lua.Status.runtime_error),
                        @intFromEnum(Lua.Status.syntax_error),
                        @intFromEnum(Lua.Status.memory_error),
                    },
                );
            },
        }
    }

    pub const DoFileError = LoadFileError || ProtectedCallError;
    pub const DoStringError = LoadError || ProtectedCallError;

    /// Loads the Lua chunk in the given file and, if there are no errors, pushes the compiled chunk as a Lua
    /// function on top of the stack before executing it using `callProtected()`. Essentially, `doFile()` executes
    /// the Lua code in the given file.
    ///
    /// From: `int luaL_dofile(lua_State *L, const char *filename);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_dofile
    /// Stack Behavior: `[-0, +?, m]`
    pub fn doFile(lua: *Lua, filename: [:0]const u8) DoFileError!void {
        try lua.loadFile(filename);
        return lua.callProtected(0, Lua.MultipleReturn, 0);
    }

    /// Loads the Lua chunk in the given string and, if there are no errors, pushes the compiled chunk as a
    /// Lua function on top of the stack before executing it using `callProtected()`. Essentially, `doString()`
    /// executes the provided zero-terminated Lua code.
    ///
    /// From: `int luaL_dostring(lua_State *L, const char *str);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_dostring
    /// Stack Behavior: `[-0, +?, m]`
    pub fn doString(lua: *Lua, str: [:0]const u8) DoStringError!void {
        try lua.loadString(str);
        return lua.callProtected(0, Lua.MultipleReturn, 0);
    }

    /// Exchange values between different threads of the same global state. This function pops n values
    /// from the stack from, and pushes them onto the stack to.
    ///
    /// From: `void lua_xmove(lua_State *from, lua_State *to, int n);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_xmove
    /// Stack Behavior: `[-?, +?, -]`
    pub fn xmove(from: *Lua, to: *Lua, n: i32) void {
        assert(n >= 0);
        assert(n <= from.getTop());

        return c.lua_xmove(asState(from), asState(to), n);
    }

    /// Used by the `gc()` to control and query aspects of the garbage collector.
    pub const GcOpcode = enum(i32) {
        /// From `LUA_GC_STOP`: Stops the garbage collector.
        stop = c.LUA_GCSTOP,

        /// LUA_GCRESTART: restarts the garbage collector.
        restart = c.LUA_GCRESTART,

        /// LUA_GCCOLLECT: performs a full garbage-collection cycle.
        collect = c.LUA_GCCOLLECT,

        /// LUA_GCCOUNT: returns the current amount of memory (in Kbytes) in use by Lua.
        count = c.LUA_GCCOUNT,

        /// LUA_GCCOUNTB: returns remainder of memory bytes in use by Lua divided by 1024.
        countBytes = c.LUA_GCCOUNTB,

        /// LUA_GCSTEP: performs an incremental step of garbage collection. The step "size" is controlled by `data`
        /// (larger values mean more steps) in a non-specified way. If you want to control the step size you must
        /// experimentally tune the value of data. The function returns 1 if the step finished a garbage-collection
        /// cycle.
        step = c.LUA_GCSTEP,

        /// LUA_GCSETPAUSE: sets data as the new value for the pause of the collector (see information on garbage
        /// collection https://www.lua.org/manual/5.1/manual.html#2.10). The function returns the previous value
        /// of the pause.
        setPause = c.LUA_GCSETPAUSE,

        /// LUA_GCSETSTEPMUL: sets data as the new value for the step multiplier of the collector (see information
        /// on garbage collection https://www.lua.org/manual/5.1/manual.html#2.10). The function returns the previous
        /// value of the step multiplier.
        setStepMul = c.LUA_GCSETSTEPMUL,
    };

    /// Controls the garbage collector with various tasks depending on the specified mode.
    ///
    /// From: `int lua_gc(lua_State *L, int what, int data);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_gc
    /// Stack Behavior: `[-0, +0, e]`
    pub fn gc(lua: *Lua, what: GcOpcode, data: i32) i32 {
        return c.lua_gc(asState(lua), @intFromEnum(what), data);
    }

    /// Returns a boolean that tells whether the garbage collector is running. The garbage collector is considered
    /// running when it is not stopped.
    ///
    /// From: `int lua_gc(lua_State *L, int what, int data);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_gc
    /// Stack Behavior: `[-0, +0, e]`
    pub fn gcIsRunning(lua: *Lua) bool {
        return 1 == c.lua_gc(asState(lua), c.LUA_GCISRUNNING, 0);
    }

    /// Starts and resumes a coroutine in a given thread. To start a coroutine, you first create a new thread then you
    /// push onto its stack the main function plus any arguments; then you call `resumeCoroutine(), with narg being the
    /// number of arguments.
    ///
    /// To restart a yielded coroutine, you put on its stack only the values to be passed as results from yield, and
    /// then call `resumeCoroutine()`.
    ///
    /// Returns `Lua.Status.yield` if the coroutine yields, `Lua.Status.ok` if the coroutine finishes its execution
    /// without errors, or an error code in case of errors. In case of errors, the stack is not unwound, so you can use
    /// the debug API over it. The error message is on the top of the stack.
    ///
    /// Note: This function was renamed from `resume` due to naming conflicts with Zig's `resume` keyword.
    ///
    /// From: `int lua_resume(lua_State *L, int narg);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_resume
    /// Stack Behavior: `[-?, +?, -]`
    fn resumeCoroutine(lua: *Lua, nargs: i32) Lua.Status {
        assert(nargs >= 0);
        const s = c.lua_resume(asState(lua), nargs);
        assert(Lua.Status.is_status(s));
        return @enumFromInt(s);
    }

    /// Yields a coroutine. This function should only be called as the return expression of a C function. When a C
    /// function calls `yieldCoroutine()`, the running coroutine suspends its execution, and the call to
    /// `resumeCoroutine()` returns. The parameter nresults is the number of values from the stack that are passed as
    /// results to `resumeCoroutine`.
    ///
    /// Note: This function was renamed from `yield` for consistency with `resumeCoroutine()`.
    ///
    /// From: `int lua_yield(lua_State *L, int nresults);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_yield
    /// Stack Behavior: `[-?, +?, -]`
    fn yieldCoroutine(lua: *Lua, nresults: i32) i32 {
        assert(nresults >= 0);
        return c.lua_yield(asState(lua), nresults);
    }

    /// Dumps the function on the top of the stack to a binary chunk. This function can be restored to the stack by
    /// calling `load()` with the binary chunk written by this function. The restored function is equivalent to the one
    /// dumped.
    ///
    /// As it produces parts of the chunk, `dump()` calls functions on the given writer instance.
    ///
    /// This function does not pop the Lua function from the stack.
    ///
    /// From: `int lua_dump(lua_State *L, lua_Writer writer, void *data);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_dump
    /// Stack Behavior: `[-0, +0, m]`
    pub fn dump(lua: *Lua, writer: std.io.AnyWriter) anyerror!void {
        const DumpContext = struct {
            writer: std.io.AnyWriter,

            fn dumpAdapter(l: *Lua, bytes: ?*const anyopaque, size: usize, ud: ?*anyopaque) callconv(.c) i32 {
                assert(bytes != null);
                assert(ud != null);

                _ = l;

                const context: *@This() = @alignCast(@ptrCast(ud));
                const slice: []const u8 = @as([*]const u8, @ptrCast(bytes))[0..size];
                context.writer.writeAll(slice) catch |err| {
                    return @intCast(@intFromError(err));
                };
                return 0;
            }
        };

        var context: DumpContext = .{
            .writer = writer,
        };

        const res = c.lua_dump(asState(lua), @ptrCast(&DumpContext.dumpAdapter), &context);

        return switch (res) {
            0 => return,
            else => |err| {
                const error_value: std.meta.Int(.unsigned, @bitSizeOf(anyerror)) = @intCast(err);
                return @errorFromInt(error_value);
            },
        };
    }

    /// The kinds of failures that can happen when the lua runtime performs a `load()` operation.
    pub const LoadError = error{
        /// The Lua content was loaded successfully, but content itself is not valid Lua. Either the data is malformed
        /// or there is a user error in the loaded content.
        InvalidSyntax,

        /// Something failed during the load process, such as the reader returning an error response instead of the
        /// next chunk of data. Note: That this is **NOT** a runtime error running the loaded code, this only indicates
        /// that a runtime error occurred during the execution of a data load.
        Runtime,

        /// The load did not complete successfully because of a memory error from the reader.
        OutOfMemory,
    };

    /// Loads the function in the given chunk and pushes the valid function to the top of the stack. If there is an
    /// error with the syntax of the function, or the data cannot be loaded, then an error is returned instead.
    ///
    /// This function only loads a chunk; it does not run it. Automatically detects whether the chunk is text or binary.
    ///
    /// From: `int lua_load(lua_State *L, lua_Reader reader, void *data, const char *chunkname);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_load
    /// Stack Behavior: `[-0, +1, -]`
    pub fn load(lua: *Lua, reader: std.io.AnyReader, chunkname: ?[:0]const u8) LoadError!void {
        const LoadContext = struct {
            reader: std.io.AnyReader,
            read_buffer: []u8,

            fn loadAdapter(l: *Lua, ud: ?*anyopaque, size: *usize) callconv(.c) [*]const u8 {
                assert(ud != null);

                const context: *@This() = @alignCast(@ptrCast(ud.?));
                const actual = context.reader.read(context.read_buffer) catch |err| {
                    _ = l.pushFString("Unable to load function, found error '%s' while reading.", .{@errorName(err).ptr});
                    l.raiseError();
                };
                size.* = actual;
                return @ptrCast(context.read_buffer.ptr);
            }
        };

        // TODO: The read buffer size should comptime constant and user controlled? Do users ever create functions that
        // are more than a few kilobytes?
        // TODO: Should the default be larger?
        var read_buffer: [1024]u8 = undefined;
        var context: LoadContext = .{
            .reader = reader,
            .read_buffer = read_buffer[0..],
        };

        const res = c.lua_load(asState(lua), @ptrCast(&LoadContext.loadAdapter), &context, if (chunkname) |p| p.ptr else null);
        return interpretLoadRes(res, "load()");
    }

    /// Used by C functions to validate received arguments.
    /// Checks whether the function argument `narg` is a number and returns this number cast to a `lua_Integer`.
    ///
    /// From: `lua_Integer luaL_checkinteger(lua_State *L, int narg);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_checkinteger
    /// Stack Behavior: `[-0, +0, v]`
    pub fn checkInteger(lua: *Lua, arg_n: i32) Lua.Integer {
        return c.luaL_checkinteger(asState(lua), arg_n);
    }

    /// Used by C functions to validate received arguments.
    /// Checks whether the function argument `arg_n` is a number and returns this number cast to a `lua_Integer`.
    /// If the function argument `arg_n` is a number, returns this number cast to a lua_Integer.
    /// If this argument is absent or is nil, returns `default`. Otherwise, raises an error.
    ///
    /// From: `lua_Integer luaL_optinteger(lua_State *L, int narg, lua_Integer d);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_optinteger
    /// Stack Behavior: `[-0, +0, v]`
    pub fn checkIntegerOptional(lua: *Lua, arg_n: i32, default: Lua.Integer) Lua.Integer {
        return c.luaL_optinteger(asState(lua), arg_n, default);
    }

    /// Used by C functions to validate received arguments.
    /// Checks whether the function argument narg is a number and returns this number.
    ///
    /// From: `lua_Number luaL_checknumber(lua_State *L, int narg);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_checknumber
    /// Stack Behavior: `[-0, +0, v]`
    pub fn checkNumber(lua: *Lua, arg_n: i32) Lua.Number {
        return c.luaL_checknumber(asState(lua), arg_n);
    }

    /// Used by C functions to validate received arguments.
    /// If the function argument is a number, returns this number. If the argument is absent or is nil,
    /// returns the default value. Otherwise, raises an error.
    ///
    /// From: `lua_Number luaL_optnumber(lua_State *L, int narg, lua_Number d);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_optnumber
    /// Stack Behavior: `[-0, +0, v]`
    pub fn checkNumberOptional(lua: *Lua, arg_n: i32, default: Lua.Number) Lua.Number {
        return c.luaL_optnumber(asState(lua), arg_n, default);
    }

    /// Used by C functions to validate received arguments.
    /// Checks whether the function argument `narg` is a string and returns this string.
    /// This function uses `lua_tolstring` to get its result, so all conversions and caveats of that function apply here.
    ///
    /// From: `const char *luaL_checkstring(lua_State *L, int narg);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_checkstring
    /// Stack Behavior: `[-0, +0, v]`
    pub fn checkString(lua: *Lua, arg_n: i32) [*:0]const u8 {
        const string: ?[*:0]const u8 = c.luaL_checklstring(asState(lua), arg_n, null);
        if (string) |s| {
            return s;
        } else {
            unreachable; // If the argument is not a string or convertable to a string, the argument check should fail and the call will not return.
        }
    }

    /// Used by C functions to validate received arguments.
    /// If the function argument `arg_n` is a string, returns this string. If this argument is absent or is nil,
    /// returns d. Otherwise, raises an error.
    ///
    /// From: `const char *luaL_optstring(lua_State *L, int narg, const char *d);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_optstring
    /// Stack Behavior: `[-0, +0, v]`
    pub fn checkStringOptional(lua: *Lua, arg_n: i32, d: [*:0]const u8) [*:0]const u8 {
        const string: ?[*:0]const u8 = c.luaL_optlstring(asState(lua), arg_n, d, null);
        if (string) |s| {
            return s;
        } else {
            unreachable; // If the argument is not a string or convertable to a string, the argument check should fail and the call will not return.
        }
    }

    /// Used by C functions to validate received arguments.
    /// Checks whether the function argument `arg_n` is a string and returns this string.
    /// All conversions and caveats of `lua.toLString()` also apply here.
    ///
    /// From: `const char *luaL_checklstring(lua_State *L, int narg, size_t *l);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_checklstring
    /// Stack Behavior: `[-0, +0, v]`
    pub fn checkLString(lua: *Lua, arg_n: i32) [:0]const u8 {
        var len: usize = undefined;
        const string: ?[*]const u8 = c.luaL_checklstring(asState(lua), arg_n, &len);
        if (string) |s| {
            return s[0..len :0];
        } else {
            unreachable; // If the argument is not a string or convertable to a string, the argument check should fail and the call will not return.
        }
    }

    /// Used by C functions to validate received arguments.
    /// If the function argument "arg_n" is a string, returns this string. If this argument is absent or is nil,
    /// returns d. Otherwise, raises an error.
    ///
    /// From: `const char *luaL_optlstring(lua_State *L, int narg, const char *d, size_t *l);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_optlstring
    /// Stack Behavior: `[-0, +0, v]`
    pub fn checkLStringOptional(lua: *Lua, arg_n: i32, default: [:0]const u8) [:0]const u8 {
        var len: usize = undefined;
        const string: ?[*]const u8 = c.luaL_optlstring(asState(lua), arg_n, default, &len);
        if (string) |s| {
            return s[0..len :0];
        } else {
            unreachable; // If the argument is not a string or convertable to a string, the argument check should fail and the call will not return.
        }
    }

    /// Used by C functions to validate received arguments.
    /// Checks whether the function argument is a userdata of the specified type.
    ///
    /// From: `void *luaL_checkudata(lua_State *L, int narg, const char *tname);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_checkudata
    /// Stack Behavior: `[-0, +0, v]`
    pub fn checkUserdata(lua: *Lua, arg_n: i32, type_name: [:0]const u8) ?*anyopaque {
        return c.luaL_checkudata(asState(lua), arg_n, type_name.ptr);
    }

    /// Used by C functions to validate received arguments.
    /// Checks whether the function argument `arg_n` is a string and searches for this string in the array `options`
    /// (which must be NULL-terminated).
    ///
    /// Returns the index in the array where the string was found or raises an error if the argument is not a string
    /// or if the string cannot be found. If `default` is not `null` then the function uses `default` as a default value
    /// when there is no argument `arg_n` or if this argument is `nil`.
    ///
    /// This is a useful function for mapping strings to enums (the usual convention in Lua libraries is to
    /// use strings instead of numbers to select options).
    ///
    /// From: `int luaL_checkoption(lua_State *L, int narg, const char *def, const char *const lst[]);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_checkoption
    /// Stack Behavior: `[-0, +0, v]`
    pub fn checkOption(lua: *Lua, arg_n: i32, options: []const [*:0]const u8, default: ?[:0]const u8) usize {
        const index = c.luaL_checkoption(
            asState(lua),
            arg_n,
            @ptrCast(if (default) |p| p.ptr else null),
            @ptrCast(options.ptr),
        );
        assert(index >= 0);
        return @intCast(index);
    }

    /// Used by C functions to validate received arguments.
    /// Checks whether the function has an argument of any type (including nil) at the specified position.
    ///
    /// From: `void luaL_checkany(lua_State *L, int narg);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_checkany
    /// Stack Behavior: `[-0, +0, v]`
    pub fn checkAny(lua: *Lua, arg_n: i32) void {
        return c.luaL_checkany(asState(lua), arg_n);
    }

    /// Used by C functions to validate received arguments.
    /// Checks whether the function argument `narg` has type `t`. See `lua_type` for the encoding of types for `t`.
    ///
    /// From: `void luaL_checktype(lua_State *L, int narg, int t);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_checktype
    /// Stack Behavior: `[-0, +0, v]`
    pub fn checkType(lua: *Lua, arg_n: i32, t: Lua.Type) void {
        return c.luaL_checktype(asState(lua), arg_n, @intCast(@intFromEnum(t)));
    }

    /// Used by C functions to validate received arguments.
    /// Checks whether the condition is true. If not, raises an error with a specific message indicating the bad
    /// argument and its number in the function call stack.
    ///
    /// Error message format: `bad argument #<arg_n> to <func> (<extra_message>)`
    ///
    /// From: `void luaL_argcheck(lua_State *L, int cond, int narg, const char *extramsg);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_argcheck
    /// Stack Behavior: `[-0, +0, v]`
    pub fn checkArgument(lua: *Lua, condition: bool, arg_n: i32, extra_message: ?[:0]const u8) void {
        if (condition) {
            _ = c.luaL_argerror(asState(lua), arg_n, if (extra_message) |m| m else null);
        }
    }

    /// Raises an error with the message "bad argument #<arg_n> to <func> (<extra_message>)". The function
    /// func is retrieved from the call stack. This function never returns, but it is an idiom
    /// to use it as a return statement.
    ///
    /// From: `int luaL_argerror(lua_State *L, int narg, const char *extramsg);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_argerror
    /// Stack Behavior: `[-0, +0, v]`
    pub fn raiseErrorArgument(lua: *Lua, arg_n: i32, extra_message: ?[:0]const u8) noreturn {
        _ = c.luaL_argerror(asState(lua), arg_n, if (extra_message) |m| m.ptr else null);
        unreachable;
    }

    /// Raises an error with a message like "<location>: bad argument #<arg_n> to '<func>' (<type_name> expected, got <actual_type>)",
    /// where `location` is produced by `where()`, `func` is the name of the current chunk, and `actual_type` is the type
    /// name of the actual argument.
    ///
    /// From: `int luaL_typerror(lua_State *L, int narg, const char *tname);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_typerror
    /// Stack Behavior: `[-0, +0, v]`
    pub fn raiseErrorType(lua: *Lua, arg_n: i32, type_name: ?[:0]const u8) noreturn {
        _ = c.luaL_typerror(asState(lua), arg_n, if (type_name) |t| t.ptr else null);
        unreachable;
    }

    /// Pushes onto the stack a string identifying the current position of the control at the given level in the call stack.
    /// Typically this string has the format: `chunkname:currentline:`.
    ///
    /// Level 0 is the running function, level 1 is the function that called the running function, etc.
    /// This function is used to build a prefix for error messages.
    ///
    /// From: `void luaL_where(lua_State *L, int lvl);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_where
    /// Stack Behavior: `[-0, +1, m]`
    pub fn where(lua: *Lua, level: i32) void {
        assert(level >= 0);
        return c.luaL_where(asState(lua), level);
    }

    /// Represents named functions that belong to a library that can be registered by a call to the `registerLibrary()`
    /// function.
    ///
    /// Any array of this type **MUST** be terminated by a sentinel value in which both `name` and `func` are set to
    /// `null`. Refer to `RegEnd`.
    ///
    /// From: `typedef struct luaL_Reg { const char *name; lua_CFunction func; } luaL_Reg;`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_Reg
    pub const Reg = struct {
        name: ?[*:0]const u8,
        func: ?Lua.CFunction,
    };
    pub const RegEnd: Reg = .{
        .name = null,
        .func = null,
    };

    /// Sets the given function as the value of a new global variable named `name`.
    ///
    /// From: `void lua_register(lua_State *L, const char *name, lua_CFunction f);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_register
    /// Stack Behavior: `[-0, +0, e]`
    pub fn registerFunction(lua: *Lua, name: [:0]const u8, function: CFunction) void {
        return c.lua_register(asState(lua), asCString(name), asCFn(function));
    }

    /// Opens a library.
    ///
    /// When called with `name` equal to null, registers all functions in the list `functions` into the table on the
    /// top of the stack. The list of functions *MUST* be terminated by the `Lua.RegEnd`
    ///
    /// When called with a non-null `name`:
    /// * creates a new table `t`,
    /// * sets `t` as the value of the global variable `name`,
    /// * sets `t` as the value of package.loaded[libname],
    /// * and registers on it all functions in the list `functions`.
    ///
    /// If there is a table in package.loaded[libname] or in variable libname, reuses this table instead of creating
    /// a new one.
    ///
    /// Calls to `registerLibrary()` always leave the library table on the top of the stack.
    ///
    /// From: `void luaL_register(lua_State *L, const char *libname, const luaL_Reg *l);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_register
    /// Stack Behavior: `[-(0|1), +1, m]`
    pub fn registerLibrary(lua: *Lua, name: ?[:0]const u8, functions: []const Lua.Reg) void {
        if (isSafeBuildTarget) {
            if (name == null) {
                assert(lua.isTable(-1));
            }
            assert(functions[functions.len - 1].name == null); // When calling `lua.registerLibrary(name, functions)`, the functions must be terminated by `RegEnd`.
            assert(functions[functions.len - 1].func == null); // When calling `lua.registerLibrary(name, functions)`, the functions must be terminated by `RegEnd`.
        }

        return c.luaL_register(
            asState(lua),
            if (name) |p| @ptrCast(p.ptr) else null,
            @ptrCast(functions.ptr),
        );
    }

    /// Performs a `[g]lobal [sub]stitution` of content in the given `string` replacing all occurrences of the substring
    /// `pattern` with the content `replacement`.
    ///
    /// Pushes the resulting string on the stack and returns it.
    ///
    /// From: `const char *luaL_gsub(lua_State *L, const char *s, const char *p, const char *r);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_gsub
    /// Stack Behavior: `[-0, +1, m]`
    pub fn gsub(lua: *Lua, string: [:0]const u8, pattern: [:0]const u8, replacement: [:0]const u8) [:0]const u8 {
        assert(pattern.len > 0); // gsub(string, "", replacement) causes an infinite loop -- avoid using the empty string as a pattern.

        const str: ?[*:0]const u8 = c.luaL_gsub(asState(lua), @ptrCast(string.ptr), @ptrCast(pattern.ptr), @ptrCast(replacement.ptr));
        if (str) |s| {
            const len = std.mem.indexOfSentinel(u8, 0, s);
            return s[0..len :0];
        } else {
            lua.raiseErrorFormat(
                "gsub('%s', '%s', '%s') returned null instead of the replaced string.",
                .{
                    string.ptr,
                    pattern.ptr,
                    replacement.ptr,
                },
            );
            unreachable;
        }
    }

    /// Type for a string buffer. A string buffer allows building Lua strings piecemeal.
    ///
    /// Pattern of use:
    /// 1. Declare a variable of type Buffer
    /// 2. Initialize with bufferInit()
    /// 3. Add string pieces using addX() functions
    /// 4. Finish by calling pushResult()
    ///
    /// From: `typedef struct luaL_Buffer luaL_Buffer;`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_Buffer
    pub const Buffer = extern struct {
        const BufferSize: usize = @intCast(c.LUAL_BUFFERSIZE);
        p: ?[*]u8 = null,
        lvl: c_int = 0,
        L: ?*Lua = null,
        buffer: [BufferSize]u8 = undefined,

        /// Adds the character c to the given buffer.
        ///
        /// From: `void luaL_addchar(luaL_Buffer *B, char c);`
        /// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_addchar
        /// Stack Behavior: `[-0, +0, m]`
        pub fn addChar(buffer: *Buffer, char: u8) void {
            assert(buffer.p != null and buffer.L != null); // You must use `Lua.initBuffer(&Lua.Buffer)` before calling `Lua.Buffer.addChar()`.

            if (buffer.p) |ptr| {
                // if the buffer is out of capacity, we will want to call `prepbuffer` to get more space and change the pointer.
                var ptr_copy = ptr;

                if (@intFromPtr(ptr) >= @intFromPtr(&buffer.buffer) + c.LUAL_BUFFERSIZE) {
                    ptr_copy = buffer.prepBuffer();
                }

                // We can assert buffer.p is non-null here since prepbuffer guarantees it
                ptr_copy[0] = char;
                buffer.p = ptr_copy + 1;
            } else {
                std.debug.panic(
                    "Failed to add character '{c}' to a buffer: the buffer is not initialized, `buffer.p` is null.\n",
                    .{char},
                );
            }
        }

        /// Adds the zero-terminated string to the buffer.
        /// The string may not contain embedded zeros.
        ///
        /// From: `void luaL_addstring(luaL_Buffer *B, const char *s);`
        /// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_addstring
        /// Stack Behavior: `[-0, +0, m]`
        pub fn addString(buffer: *Buffer, string: [*:0]const u8) void {
            assert(buffer.p != null and buffer.L != null); // You must use `Lua.initBuffer(&Lua.Buffer)` before calling `Lua.Buffer.addString()`.

            return c.luaL_addstring(@ptrCast(buffer), string);
        }

        /// Adds the string to the buffer.
        /// The string may contain embedded zeros.
        ///
        /// From: `void luaL_addlstring(luaL_Buffer *B, const char *s, size_t l);`
        /// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_addlstring
        /// Stack Behavior: `[-0, +0, m]`
        pub fn addLString(buffer: *Buffer, string: [:0]const u8) void {
            assert(buffer.p != null and buffer.L != null); // You must use `Lua.initBuffer(&Lua.Buffer)` before calling `Lua.Buffer.addLString()`.

            return c.luaL_addlstring(@ptrCast(buffer), string.ptr, string.len);
        }

        /// Adds the value at the top of the stack to the buffer (see https://www.lua.org/manual/5.1/manual.html#luaL_Buffer).
        /// Pops the value. This is the only function on string buffers that can (and must) be called with an extra
        /// element on the stack, which is the value to be added to the buffer.
        ///
        /// From: `void luaL_addvalue(luaL_Buffer *B);`
        /// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_addvalue
        /// Stack Behavior: `[-1, +0, m]`
        pub fn addValue(buffer: *Buffer) void {
            assert(buffer.p != null and buffer.L != null); // You must use `Lua.initBuffer(&Lua.Buffer)` before calling `Lua.Buffer.addLString()`.
            assert(buffer.L.?.getTop() > 0);

            return c.luaL_addvalue(@ptrCast(buffer));
        }

        /// Prepares writable space in the buffer.
        ///
        /// Used to provide direct writing of data. The caller **MUST** call `buffer.addSize()` after writing content
        /// to the returned address of memory. If you do not call `buffer.addSize()` then the content will not be added
        /// to the result of the Buffer.
        /// ```
        /// var space = buffer.prepBuffer();
        /// @memcpy(space, "Hello", 5);
        /// buffer.addSize(5);  // Required when directly writing
        ///
        /// Returns a pointer to space of size `BufferSize` bytes.
        ///
        /// From: `char *luaL_prepbuffer(luaL_Buffer *B);`
        /// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_prepbuffer
        /// Stack Behavior: `[-0, +0, -]`
        pub fn prepBuffer(buffer: *Buffer) [*]u8 {
            assert(buffer.p != null and buffer.L != null); // You must use `Lua.initBuffer(&Lua.Buffer)` before calling `Lua.Buffer.prepBuffer()`.

            const ptr: ?[*]u8 = @ptrCast(c.luaL_prepbuffer(@ptrCast(buffer)));
            assert(ptr != null);
            return ptr.?;
        }

        /// Adds to the buffer a string of length `n` previously copied to the buffer area. Callers should write to the
        /// buffer area returned from `prepBuffer()`.
        ///
        /// From: `void luaL_addsize(luaL_Buffer *B, size_t n);`
        /// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_addsize
        /// Stack Behavior: `[-0, +0, m]`
        pub fn addSize(buffer: *Buffer, n: usize) void {
            assert(buffer.p != null and buffer.L != null); // You must use `Lua.initBuffer(&Lua.Buffer)` before calling `Lua.Buffer.addSize()`.

            if (buffer.p) |ptr| {
                buffer.p = ptr + n;
            } else {
                std.debug.panic(
                    "Failed to buffer.addSize('{d}'): the buffer is not initialized, `buffer.p` is null.\n",
                    .{n},
                );
            }
        }

        /// Finishes the use of the buffer leaving the final string on the top of the stack.
        ///
        /// From: `void luaL_pushresult(luaL_Buffer *B);`
        /// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_pushresult
        /// Stack Behavior: `[-?, +1, m]`
        pub fn pushResult(buffer: *Lua.Buffer) void {
            assert(buffer.p != null and buffer.L != null); // You must use `Lua.initBuffer(&Lua.Buffer)` before calling `Lua.Buffer.pushResult()`.

            return c.luaL_pushresult(@ptrCast(buffer));
        }
    };

    /// Initializes a Lua buffer. This function does not allocate any space;
    /// the buffer must be declared as a variable.
    ///
    /// From: `void luaL_buffinit(lua_State *L, luaL_Buffer *B);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_buffinit
    /// Stack Behavior: `[-0, +0, -]`
    pub fn initBuffer(lua: *Lua, buffer: *Lua.Buffer) void {
        return c.luaL_buffinit(asState(lua), @ptrCast(buffer));
    }

    /// Represents different types of events that can be triggered during Lua execution. These events are received by
    /// hooks to inspect or modify the execution of code in the Lua instance.
    pub const HookEventKind = enum(i32) {
        /// Function call event
        call = c.LUA_HOOKCALL,
        /// Normal function return event
        ret = c.LUA_HOOKRET,
        /// Line execution event
        line = c.LUA_HOOKLINE,
        /// Instruction count event
        count = c.LUA_HOOKCOUNT,
        /// Tail call return event - occurs when Lua is simulating a return from a function that performed a tail call
        tailret = c.LUA_HOOKTAILRET,

        /// This value is NOT part of the Lua ABI, but provided so we can set a safe default value and detect an
        /// uninitialized instance of this struct.
        none = -1,

        pub fn isHookEventKind(v: i32) bool {
            return v == @intFromEnum(HookEventKind.call) //
            or v == @intFromEnum(HookEventKind.ret) //
            or v == @intFromEnum(HookEventKind.line) //
            or v == @intFromEnum(HookEventKind.count) //
            or v == @intFromEnum(HookEventKind.tailret);
        }
    };

    pub const DebugShortSourceLen = @as(usize, @intCast(c.LUA_IDSIZE));

    /// A structure used to carry different pieces of information about an active function.
    /// lua_getstack fills only the private part of this structure, for later use.
    /// To fill the other fields with useful information, call lua_getinfo.
    ///
    /// Note: While Lua is running a hook, it disables other calls to hooks. If a hook calls back
    /// Lua to execute a function or a chunk, this execution occurs without any calls to hooks.
    pub const DebugInfo = extern struct {
        /// The event that triggered the hook. When hooks are called, this field indicates
        /// the specific event type that triggered it
        event: Lua.HookEventKind = .none,

        /// A reasonable name for the active function. Because functions in Lua are first-class values, they do not
        /// have a fixed name: some functions can be the value of multiple global variables, while others can be stored
        /// only in a table field.
        ///
        /// The `getInfo()` function checks how the function was called to find a suitable name.
        /// If it cannot find a name, then name is set to NULL.
        name: ?[*:0]const u8 = null,

        /// Explains the context of the `name` field. Contains one of the following values:
        /// * `"global"` - function is in a global variable
        /// * `"local"` - function is in a local variable
        /// * `"method"` - function is a method
        /// * `"field"` - function is in a table field
        /// * `"upvalue"` - function is in an upvalue
        /// * `""` (empty string) - when no other option applies
        namewhat: ?[*:0]const u8 = null,

        /// Indicates the type of function being executed. Contains one of the following values:
        /// * `"Lua"` - the active function is a Lua function
        /// * `"C"` - the active function is a C function
        /// * `"main"` - the active function is the main part of a chunk
        /// * `"tail"` - the active function did a tail call. In this case, Lua has no other information about the function
        what: ?[*:0]const u8 = null,

        /// The source code that the language element originates from.
        ///
        /// * If the function was defined in a string, then `source` is that string
        /// * If the function was defined in a file, then `source` starts with '@' followed by the file name
        source: ?[*:0]const u8 = null,

        /// Current line where the given function is executing.
        /// Set to -1 when no line information is available
        currentline: i32 = -1,

        /// Number of upvalues in the function
        nups: i32 = undefined,

        /// Line number where the definition of the function starts
        linedefined: i32 = undefined,

        /// Line number where the definition of the function ends
        lastlinedefined: i32 = undefined,

        /// A printable version of `source`, optimized for error messages.
        /// Contains a shortened version of the source location
        short_src: [DebugShortSourceLen]u8 = undefined,

        pub fn prettyPrint(self: *Lua.DebugInfo, writer: std.io.AnyWriter) !void {
            try writer.print("{*} {{\n", .{self});
            if (HookEventKind.isHookEventKind(@intFromEnum(self.event))) {
                try writer.print("  event: '{s}' ({d}),\n", .{ @tagName(self.event), @intFromEnum(self.event) });
            } else {
                try writer.print("  event: '?' ({d}),\n", .{@intFromEnum(self.event)});
            }

            if (self.name) |name| {
                try writer.print("  name: '{s}',\n", .{name});
            } else {
                try writer.writeAll("  name: '<null>',\n");
            }

            if (self.namewhat) |namewhat| {
                try writer.print("  namewhat: '{s}',\n", .{namewhat});
            } else {
                try writer.writeAll("  namewhat: '<null>',\n");
            }

            if (self.what) |what| {
                try writer.print("  what: '{s}',\n", .{what});
            } else {
                try writer.writeAll("  what: '<null>',\n");
            }

            if (std.mem.indexOf(u8, self.short_src[0..DebugShortSourceLen], &.{0})) |i| {
                try writer.print("  short_src: `{s}`,\n", .{self.short_src[0..i]});
            }

            try writer.print("  currentline: {d},\n", .{self.currentline});
            try writer.print("  nups: {d},\n", .{self.nups});
            try writer.print("  linedefined: {d},\n", .{self.linedefined});
            try writer.print("  lastlinedefined: {d},\n", .{self.lastlinedefined});

            if (self.source) |source| {
                try writer.print("  source:\n```\n{s}\n```\n", .{source[0..@min(256, std.mem.indexOfSentinel(u8, 0, source))]});
            } else {
                try writer.writeAll("  source: '<null>'\n");
            }

            try writer.writeAll("}\n");
        }
    };

    /// Returns information about a specific function or function invocation.
    ///
    /// To get information about a function invocation, the parameter `info` must be a valid activation record that was
    /// filled by a previous call to `getStack()` or provided as an argument to a hook.
    ///
    /// To get information about a function, push it onto the stack and start the `what` string with the character '>'.
    /// In that case, `getInfo()` pops the function from the top of the stack.
    ///
    /// Each character in the `what` string selects some fields of the `DebugInfo` structure to be filled or a value
    /// to be pushed on the stack:
    /// - 'n': fills in the `name` and `namewhat` fields
    /// - 'S': fills in the `source`, `short_src`, `line_defined`, `lastlinedefined`, and `what` fields
    /// - 'l': fills in the `currentline` field
    /// - 'u': fills in the `nups` field
    /// - 'f': pushes onto the stack the function running at the given level
    /// - 'L': pushes onto the stack a table with indices of valid lines for the function
    ///
    /// Returns `true` when the operation was performed succesfully and `false` otherwise (e.g. when given an invalid `what`).
    ///
    /// From: `int lua_getinfo(lua_State *L, const char *what, lua_Debug *ar);`
    /// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_getinfo
    /// Stack Behavior: `[-(0|1), +(0|1|2), m]`
    pub fn getInfo(lua: *Lua, what: [:0]const u8, info: *Lua.DebugInfo) bool {
        return 0 != c.lua_getinfo(asState(lua), what.ptr, @ptrCast(info));
    }

    /// Represents the different kinds of functions that can be inspected by `getInfo()`. This enumerates the possible
    /// values that `getInfo()` will set in the `what` field when inspecting a function.
    pub const FunctionKind = enum {
        lua,
        c,
        main,
        tail,
        unknown,

        pub fn parse(what: ?[*:0]const u8) FunctionKind {
            if (what) |w| {
                const slice = w[0..std.mem.indexOfSentinel(u8, 0, w)];
                if (std.mem.eql(u8, "Lua", slice)) {
                    return .lua;
                } else if (std.mem.eql(u8, "C", slice)) {
                    return .lua;
                } else if (std.mem.eql(u8, "main", slice)) {
                    return .lua;
                } else if (std.mem.eql(u8, "tail", slice)) {
                    return .lua;
                } else {
                    return .unknown;
                }
            } else {
                return .unknown;
            }
        }
    };

    /// A friendly form of the `DebugInfo` struct containing information returned by `getInfoFunction()`. The alternative
    /// is to use `getInfo()` with the function inspection prefix `'>'` and `'S'` or `'u'` for source information and
    /// upvalues information, respectively.
    pub const DebugInfoFunction = struct {
        /// Indicates the type of the function.
        what: Lua.FunctionKind = .unknown,

        /// The source code that the language element originates from.
        ///
        /// * If the function was defined in a string, then `source` is that string
        /// * If the function was defined in a file, then `source` starts with '@' followed by the file name
        source: ?[:0]const u8 = null,

        /// Number of upvalues in the function
        nups: i32 = undefined,

        /// Line number where the definition of the function starts
        linedefined: i32 = undefined,

        /// Line number where the definition of the function ends
        lastlinedefined: i32 = undefined,

        /// A printable version of `source`, optimized for error messages.
        /// Contains a shortened version of the source location
        short_src: [DebugShortSourceLen]u8 = undefined,

        pub fn prettyPrint(self: *Lua.DebugInfoFunction, writer: std.io.AnyWriter) !void {
            try writer.print("{*} {{\n", .{self});
            try writer.print("  what: '{s}',\n", .{@tagName(self.what)});

            if (std.mem.indexOf(u8, self.short_src[0..DebugShortSourceLen], &.{0})) |i| {
                try writer.print("  short_src: `{s}`,\n", .{self.short_src[0..i]});
            }

            try writer.print("  nups: {d},\n", .{self.nups});
            try writer.print("  linedefined: {d},\n", .{self.linedefined});
            try writer.print("  lastlinedefined: {d},\n", .{self.lastlinedefined});

            if (self.source) |source| {
                try writer.print("  source:\n```\n{s}\n```\n", .{source});
            } else {
                try writer.writeAll("  source: '<null>'\n");
            }

            try writer.writeAll("}\n");
        }
    };

    /// A less efficient but simpler version of `getInfo()` for discovering debug information about the function on the
    /// top of the stack.
    ///
    /// Asserts that the top of the stack contains a function and returns an error when the underlying call to `getInfo()`
    /// returns `false`.
    ///
    /// Stack Behavior: `[-1, +0, m]`
    pub fn getInfoFunction(lua: *Lua) error{NoDebugInfo}!Lua.DebugInfoFunction {
        assert(lua.isFunction(-1));
        var info: Lua.DebugInfo = undefined;
        if (!lua.getInfo(">Su", &info)) {
            return error.NoDebugInfo;
        }
        var simplifiedInterface = Lua.DebugInfoFunction{
            .what = FunctionKind.parse(info.what),
            .source = if (info.source) |s| s[0..std.mem.indexOfSentinel(u8, 0, s) :0] else null,
            .nups = info.nups,
            .linedefined = info.linedefined,
            .lastlinedefined = info.lastlinedefined,
        };
        @memcpy(simplifiedInterface.short_src[0..DebugShortSourceLen], info.short_src[0..DebugShortSourceLen]);
        return simplifiedInterface;
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

    try std.testing.expect(lua.getType(1) == Lua.Type.none);
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
    try std.testing.expect(lua.getType(1) == Lua.Type.nil);
    try std.testing.expect(lua.isNil(1));
    try std.testing.expect(lua.isNoneOrNil(1));
    try std.testing.expect(!(lua.getType(1) == Lua.Type.none));
    try std.testing.expect(!lua.isNone(1));
    try std.testing.expectEqualSlices(u8, "nil", lua.getTypeNameAt(1));
    lua.pop(1);

    lua.pushBoolean(true);
    try std.testing.expect(lua.getType(1) == Lua.Type.boolean);
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
    try std.testing.expectEqualSlices(u8, "boolean", lua.getTypeNameAt(1));
    lua.pop(1);

    lua.pushInteger(42);
    try std.testing.expect(lua.getType(1) == Lua.Type.number);
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
    try std.testing.expectEqualSlices(u8, "number", lua.getTypeNameAt(1));
    lua.pop(1);

    lua.pushNumber(42.4);
    try std.testing.expect(lua.getType(1) == Lua.Type.number);
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
    try std.testing.expectEqualSlices(u8, "number", lua.getTypeNameAt(1));
    lua.pop(1);

    lua.pushString("abc");
    try std.testing.expect(lua.isString(1));
    try std.testing.expectEqualSlices(u8, "string", lua.getTypeNameAt(1));
    lua.pop(1);

    lua.pushLString("abc");
    try std.testing.expect(lua.isString(1));
    try std.testing.expectEqualSlices(u8, "string", lua.getTypeNameAt(1));
    lua.pop(1);

    lua.newTable();
    try std.testing.expect(lua.isTable(1));
    try std.testing.expectEqual(Lua.Type.table, lua.getType(1));
    try std.testing.expectEqualSlices(u8, "table", lua.getTypeNameAt(1));
    lua.pop(1);

    lua.createTable(1, 0);
    try std.testing.expect(lua.isTable(1));
    try std.testing.expectEqual(Lua.Type.table, lua.getType(1));
    lua.pop(1);

    try std.testing.expectEqualSlices(u8, "no value", lua.getTypeName(Lua.Type.none));
    try std.testing.expectEqualSlices(u8, "nil", lua.getTypeName(Lua.Type.nil));
    try std.testing.expectEqualSlices(u8, "boolean", lua.getTypeName(Lua.Type.boolean));
    try std.testing.expectEqualSlices(u8, "userdata", lua.getTypeName(Lua.Type.userdata));
    try std.testing.expectEqualSlices(u8, "number", lua.getTypeName(Lua.Type.number));
    try std.testing.expectEqualSlices(u8, "string", lua.getTypeName(Lua.Type.string));
    try std.testing.expectEqualSlices(u8, "table", lua.getTypeName(Lua.Type.table));
    try std.testing.expectEqualSlices(u8, "function", lua.getTypeName(Lua.Type.function));
    try std.testing.expectEqualSlices(u8, "userdata", lua.getTypeName(Lua.Type.light_userdata));
    try std.testing.expectEqualSlices(u8, "thread", lua.getTypeName(Lua.Type.thread));
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

test "insert on the stack" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    lua.pushInteger(42);
    lua.pushBoolean(true);
    lua.insert(-2);
    try std.testing.expect(lua.isBoolean(1) and lua.isBoolean(-2));
    try std.testing.expect(lua.isNumber(2) and lua.isNumber(-1));
    lua.pop(2);
}

test "remove item from the stack" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    lua.pushInteger(42);
    lua.pushBoolean(true);
    lua.remove(-2);
    try std.testing.expect(lua.isBoolean(1) and lua.isBoolean(-1));
    lua.pop(1);
}

test "replace item on the stack" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    lua.pushInteger(42);
    lua.pushBoolean(true);
    lua.replace(-2);
    try std.testing.expect(lua.isBoolean(1) and lua.isBoolean(-1));
    lua.pop(1);
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

test "string formatting with pushFString" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    const expected: [:0]const u8 = "abc%_FOO_42";
    const actual = lua.pushFString("abc%%_%s_%d", .{ "FOO", @as(i32, 42) });

    try std.testing.expectEqualSlices(u8, expected, actual);
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

test "checkStackOrError should return raise an error for stack overflow" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    const T = struct {
        fn Fn(l: *Lua) callconv(.c) i32 {
            l.checkStackOrError(9000, "CUSTOM ERROR MESSAGE");
            return 0;
        }
    };

    lua.pushCFunction(T.Fn);
    const actual = lua.callProtected(0, 0, 0);
    try std.testing.expectError(Lua.CallError.Runtime, actual);
    try std.testing.expectEqualSlices(u8, "stack overflow (CUSTOM ERROR MESSAGE)", try lua.toLString(-1));
}

const FailingAllocator = struct {
    fn allocator(self: *@This()) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .remap = remap,
                .free = free,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        _ = ctx;
        _ = len;
        _ = ptr_align;
        _ = ret_addr;
        return null;
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        _ = ctx;
        _ = buf;
        _ = buf_align;
        _ = new_len;
        _ = ret_addr;
        return false;
    }

    fn remap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        _ = ctx;
        _ = memory;
        _ = alignment;
        _ = new_len;
        _ = ret_addr;
        return null;
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
        _ = ctx;
        _ = buf;
        _ = buf_align;
        _ = ret_addr;
    }
};

test "checkStack should return OOM when allocation fails." {
    var fa: FailingAllocator = .{};

    const lua = try Lua.init(std.testing.allocator);
    lua.setAllocator(fa.allocator());
    defer {
        lua.setAllocator(std.testing.allocator);
        lua.deinit();
    }

    try std.testing.expectError(error.OutOfMemory, lua.checkStack(100));
}

test "checkStackOrError should return raise an error during allocation failure" {
    var fa: FailingAllocator = .{};

    const lua = try Lua.init(std.testing.allocator);
    defer {
        lua.setAllocator(std.testing.allocator);
        lua.deinit();
    }

    const T = struct {
        fn Fn(l: *Lua) callconv(.c) i32 {
            l.checkStackOrError(100, "CUSTOM ERROR MESSAGE");
            return 0;
        }
    };

    lua.pushCFunction(T.Fn);
    lua.setAllocator(fa.allocator());
    const actual = lua.callProtected(0, 0, 0);
    try std.testing.expectError(Lua.CallError.OutOfMemory, actual);
    try std.testing.expectEqualSlices(u8, "not enough memory", try lua.toLString(-1));
}

test "status should be ok after ok executions" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    try std.testing.expectEqual(Lua.Status.ok, lua.status());
    lua.pushLString("Foo bar");
    try std.testing.expectEqual(Lua.Status.ok, lua.status());
    lua.pop(1);
    try std.testing.expectEqual(Lua.Status.ok, lua.status());
    lua.openLibs();
    try lua.doString(
        \\ print("Hello, world!")
    );
    try std.testing.expectEqual(Lua.Status.ok, lua.status());
}

test "status should reflect appropriate states of the Lua machine after failures" {
    var fa: FailingAllocator = .{};
    const lua = try Lua.init(std.testing.allocator);
    lua.setAllocator(fa.allocator());
    defer {
        lua.setAllocator(std.testing.allocator);
        lua.deinit();
    }

    const actual = lua.doString(
        \\ return {}
    );
    try std.testing.expectError(Lua.DoStringError.OutOfMemory, actual);
    try std.testing.expectEqual(Lua.Status.ok, lua.status()); // I think the reason it's OK is because the machine is ready to continue running, despite the failure? I'm actually not sure why I cannot get status to return an error code despite trying many things. Leaving it untested for now, sorry if you find this :(
}

test "tables" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    lua.newTable();
    lua.pushInteger(1);
    lua.pushLString("Hello, world!");
    try std.testing.expectEqual(3, lua.getTop());

    lua.setTable(-3);
    try std.testing.expectEqual(1, lua.getTop());

    lua.pushInteger(1);
    try std.testing.expectEqual(Lua.Type.string, lua.getTable(-2));
    lua.pop(1);

    lua.pushInteger(1);
    lua.pushBoolean(true);
    lua.setTableRaw(-3);
    try std.testing.expectEqual(1, lua.getTop());
    lua.pushInteger(1);
    try std.testing.expectEqual(Lua.Type.boolean, lua.getTableRaw(-2));
    try std.testing.expect(try lua.toBooleanStrict(-1));
}

test "getfield and setfield" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    lua.newTable();
    lua.pushInteger(42);
    lua.setField(-2, "foo");

    try std.testing.expectEqual(1, lua.getTop());

    const actual_type = lua.getField(-1, "foo");
    try std.testing.expectEqual(Lua.Type.number, actual_type);
    try std.testing.expectEqual(42, lua.toInteger(-1));
}

test "getglobal and setglobal" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    lua.pushInteger(42);
    lua.setGlobal("XXX");

    try std.testing.expectEqual(0, lua.getTop());

    const actual_type = lua.getGlobal("XXX");
    try std.testing.expectEqual(Lua.Type.number, actual_type);
    try std.testing.expectEqual(42, lua.toInteger(-1));
}

test "getLength" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    lua.newTable();
    lua.pushInteger(1);
    lua.pushString("Hello, world!");
    lua.setTable(-3);
    lua.pushInteger(2);
    lua.pushString("Ayo");
    try std.testing.expectEqual(3, lua.getLength(-1));
    lua.setTable(-3);
    try std.testing.expectEqual(2, lua.getLength(-1));
    lua.pop(1);

    lua.pushInteger(257);
    try std.testing.expectEqual(3, lua.getLength(-1)); // Implicit conversion to string
    lua.pop(1);
    lua.pushNumber(145.125);
    try std.testing.expectEqual(7, lua.getLength(-1)); // Implicit conversion to string
    lua.pop(1);

    lua.pushNil();
    try std.testing.expectEqual(0, lua.getLength(-1));
    lua.pop(1);
}

fn dummyCFunction(lua: *Lua) callconv(.c) i32 {
    _ = lua;
    return 0;
}

fn dummyCClosure(lua: *Lua) callconv(.c) i32 {
    const n = lua.toNumber(Lua.PseudoIndex.upvalue(1));
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

test "c functions and closures with callProtected" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    lua.pushCFunction(dummyCFunction);
    try std.testing.expectEqual(1, lua.getTop());
    try std.testing.expect(lua.isCFunction(1) and lua.isCFunction(-1));
    try std.testing.expect(lua.isFunction(1) and lua.isFunction(-1));
    try lua.callProtected(0, 0, 0);
    try std.testing.expectEqual(0, lua.getTop());

    const expected: i64 = 42;
    lua.pushInteger(expected);
    lua.pushCClosure(dummyCClosure, 1);
    try std.testing.expectEqual(1, lua.getTop());
    try std.testing.expect(lua.isCFunction(1) and lua.isCFunction(-1));
    try std.testing.expect(lua.isFunction(1) and lua.isFunction(-1));
    try lua.callProtected(0, 1, 0);
    try std.testing.expectEqual(1, lua.getTop());
    const actual = lua.toInteger(-1);
    try std.testing.expectEqual(expected, actual);
    lua.pop(1);
}

test "callProtected should capture error raised by c function" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    const T = struct {
        fn errorRaisingCFunction(l: *Lua) callconv(.c) i32 {
            l.pushLString("error raised");
            l.raiseError();
        }
    };

    lua.pushCFunction(T.errorRaisingCFunction);
    const actual = lua.callProtected(0, 0, 0);
    try std.testing.expectError(Lua.CallError.Runtime, actual);
    try std.testing.expectEqualSlices(u8, "error raised", try lua.toLString(-1));
}

test "callProtected should capture formatted error raised by c function" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    const T = struct {
        fn formattedErrorRaisingCFunction(l: *Lua) callconv(.c) i32 {
            return l.raiseErrorFormat("%%-%s-%%,%f,%d,'%c'", .{ "Hello", @as(f64, 13.3), @as(i32, 42), @as(u8, 'A') });
        }
    };

    lua.pushCFunction(T.formattedErrorRaisingCFunction);
    const actual = lua.callProtected(0, 0, 0);
    try std.testing.expectError(Lua.CallError.Runtime, actual);
    try std.testing.expectEqualSlices(u8, "%-Hello-%,13.3,42,'A'", try lua.toLString(-1));
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

test "equal should follow expected semantics" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    lua.pushLString("Hello, world!");
    lua.pushLString("hello, world!");
    try std.testing.expect(!lua.equal(-2, -1));
    lua.pop(1);
    lua.pushLString("Hello, world!");
    try std.testing.expect(lua.equal(-2, -1));
    lua.pop(2);

    lua.pushNumber(13.0);
    lua.pushInteger(13);
    try std.testing.expect(lua.equal(-2, -1));
    lua.pop(2);

    lua.pushNumber(13.5);
    lua.pushNumber(13.4);
    try std.testing.expect(!lua.equal(-2, -1));
    lua.pop(2);

    lua.pushNil();
    lua.pushBoolean(true);
    try std.testing.expect(!lua.equal(-2, -1));
    lua.pop(2);

    lua.pushNil();
    lua.pushNil();
    try std.testing.expect(lua.equal(-2, -1));
    lua.pop(2);

    lua.pushBoolean(true);
    lua.pushBoolean(false);
    try std.testing.expect(!lua.equal(-2, -1));
    lua.pop(2);

    lua.pushBoolean(true);
    lua.pushBoolean(true);
    try std.testing.expect(lua.equal(-2, -1));
}

test "equalRaw should follow expected semantics" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    lua.pushLString("Hello, world!");
    lua.pushLString("hello, world!");
    try std.testing.expect(!lua.equalRaw(-2, -1));
    lua.pop(1);
    lua.pushLString("Hello, world!");
    try std.testing.expect(lua.equalRaw(-2, -1));
    lua.pop(2);

    lua.pushNumber(13.0);
    lua.pushInteger(13);
    try std.testing.expect(lua.equalRaw(-2, -1));
    lua.pop(2);

    lua.pushNumber(13.5);
    lua.pushNumber(13.4);
    try std.testing.expect(!lua.equalRaw(-2, -1));
    lua.pop(2);

    lua.pushNil();
    lua.pushBoolean(true);
    try std.testing.expect(!lua.equalRaw(-2, -1));
    lua.pop(2);

    lua.pushNil();
    lua.pushNil();
    try std.testing.expect(lua.equalRaw(-2, -1));
    lua.pop(2);

    lua.pushBoolean(true);
    lua.pushBoolean(false);
    try std.testing.expect(!lua.equalRaw(-2, -1));
    lua.pop(2);

    lua.pushBoolean(true);
    lua.pushBoolean(true);
    try std.testing.expect(lua.equalRaw(-2, -1));
}

test "lessthan should follow expected semantics" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    lua.pushNumber(13.0);
    lua.pushInteger(13);
    try std.testing.expect(!lua.lessThan(-2, -1));
    try std.testing.expect(!lua.lessThan(-1, -2));
    lua.pop(2);

    lua.pushNumber(13.5);
    lua.pushNumber(13.4);
    try std.testing.expect(!lua.lessThan(-2, -1));
    try std.testing.expect(lua.lessThan(-1, -2));
    lua.pop(2);

    lua.pushLString("a");
    lua.pushLString("b");
    try std.testing.expect(lua.lessThan(-2, -1));
    try std.testing.expect(!lua.lessThan(-1, -2));
    lua.pop(2);
}

test "concat should follow expected semantics" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    lua.concat(0);
    try std.testing.expectEqualSlices(u8, "", try lua.toLString(-1));
    lua.pop(1);

    lua.pushInteger(42);
    lua.concat(1);
    try std.testing.expectEqualSlices(u8, "42", try lua.toLString(-1));
    lua.pop(1);

    lua.pushNumber(13.1);
    lua.pushInteger(13);
    lua.concat(2);
    try std.testing.expectEqualSlices(u8, "13.113", try lua.toLString(-1));
    lua.pop(1);

    lua.pushInteger(42);
    lua.pushLString("-");
    lua.pushInteger(84);
    lua.pushLString("-Boof");
    lua.concat(4);
    try std.testing.expectEqualSlices(u8, "42-84-Boof", try lua.toLString(-1));
    lua.pop(1);
}

fn always42AddMetamethod(lua: *Lua) callconv(.c) i32 {
    lua.pushInteger(42);
    return 1;
}

test "metatables can be set" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    lua.openBaseLib();

    lua.newTable();
    lua.newTable();
    lua.pushLString("__add");
    lua.pushCFunction(always42AddMetamethod);
    lua.setTable(-3);
    lua.setMetatable(-2);

    try std.testing.expect(lua.getMetatable(-1));
    try std.testing.expect(lua.isTable(-1));
    lua.setTop(0);
}

test "metatables can be accessed" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    lua.openBaseLib();

    try lua.doString(
        \\f = {}
        \\return setmetatable(f, {
        \\    __add = function (l, r)
        \\        return 0
        \\    end
        \\})
    );
    try std.testing.expect(lua.isTable(-1));
    try std.testing.expect(lua.getMetatable(-1));
    try std.testing.expect(lua.isTable(-1));

    lua.pushLString("__add");
    try std.testing.expectEqual(Lua.Type.function, lua.getTable(-2));
    lua.setTop(0);
}

test "proctected call for c functions" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    const T = struct {
        fn cFunctionForProtectedCall(l: *Lua) callconv(.c) i32 {
            std.testing.expectEqual(1, l.getTop()) catch std.debug.panic("Test assertion failed.", .{});
            std.testing.expect(l.isLightUserdata(1)) catch std.debug.panic("Test assertion failed.", .{});

            l.pushLString("EXPECTED ERROR 123");
            return l.raiseError();
        }
    };

    const actual = lua.callProtectedC(T.cFunctionForProtectedCall, null);
    try std.testing.expectError(Lua.CallError.Runtime, actual);
    try std.testing.expectEqualSlices(u8, "EXPECTED ERROR 123", try lua.toLString(-1));
}

test "override error function with atpanic" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    // This test case is actually kind of useless, I don't want to hack doing a long jump into these tests
    // to avoid application exit. So we will just call the function and make sure the application doesn't
    // crash. But it's not really testing that the panic function gets called in any way right now.
    const T = struct {
        fn newPanicFunction(l: *Lua) callconv(.c) i32 {
            _ = l;
            return 0;
        }
    };

    const actual = lua.atPanic(T.newPanicFunction);
    try std.testing.expect(actual == null);
    const new = lua.atPanic(actual);
    try std.testing.expect(new.? == T.newPanicFunction);
}

test "garbage collector controls" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    try std.testing.expect(9 < lua.gc(.count, 0) and lua.gc(.count, 0) < 13);
    try std.testing.expect(lua.gcIsRunning());
    try std.testing.expectEqual(0, lua.gc(.stop, 0));
    try std.testing.expect(!lua.gcIsRunning());
}

test "push and get light userdata" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    var i: i32 = 0;

    lua.pushLightUserdata(@ptrCast(&i));
    lua.pushLightUserdata(@ptrCast(&i));
    try std.testing.expect(lua.equal(-1, -2));

    const a1 = lua.toUserdata(-1);
    const a2 = lua.toUserdata(-2);
    try std.testing.expectEqual(a1.?, @as(*anyopaque, @ptrCast(&i)));
    try std.testing.expectEqual(a1.?, a2.?);
}

test "pushvalue" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    lua.pushInteger(42);
    lua.pushValue(-1);
    try std.testing.expect(lua.equal(-1, -2));

    const a1 = lua.toInteger(-1);
    const a2 = lua.toInteger(-2);
    try std.testing.expectEqual(a1, a2);

    lua.setTop(0);
    lua.pushLString("ASDF");
    lua.pushValue(-1);
    try std.testing.expect(lua.equal(-1, -2));

    const s1 = try lua.toLString(-1);
    const s2 = try lua.toLString(-2);
    try std.testing.expectEqualStrings(s1, s2);
}

test "getTableIndexRaw" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    lua.newTable();
    lua.pushInteger(42);
    lua.setTableIndexRaw(1, 1);

    const actual_type = lua.getTableIndexRaw(1, 1);
    try std.testing.expectEqual(Lua.Type.number, actual_type);
    try std.testing.expectEqual(42, lua.toIntegerStrict(-1));
    try std.testing.expectEqual(2, lua.getTop());
}

test "registering named functions" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    const T = struct {
        fn registeredFn(l: *Lua) callconv(.c) i32 {
            l.pushLString("Galt, John");
            return 1;
        }
    };

    lua.registerFunction("regREG", T.registeredFn);
    try lua.doString(
        \\actual = regREG()
        \\if actual == 'Galt, John' then
        \\    return 1
        \\end
        \\return 0
    );
    try std.testing.expect(lua.isInteger(-1));
    try std.testing.expectEqual(1, lua.toIntegerStrict(-1));
}

test "registering a library to the global namespace" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    const T = struct {
        fn john(l: *Lua) callconv(.c) i32 {
            l.pushLString("Galt");
            return 1;
        }
        fn hank(l: *Lua) callconv(.c) i32 {
            l.pushLString("Reardon");
            return 1;
        }
    };

    lua.registerLibrary(
        "foo",
        &[_]Lua.Reg{
            .{ .name = "john", .func = &T.john },
            .{ .name = "hank", .func = &T.hank },
            Lua.RegEnd,
        },
    );
    try lua.doString(
        \\john, hank = foo.john(), foo.hank()
        \\if (john == 'Galt' and hank == 'Reardon') then
        \\    return 1
        \\end
        \\return 0
    );
    try std.testing.expect(lua.isInteger(-1));
    try std.testing.expectEqual(1, lua.toIntegerStrict(-1));
}

test "registering a library to a table" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    const T = struct {
        fn john(l: *Lua) callconv(.c) i32 {
            l.pushLString("Galt");
            return 1;
        }
        fn hank(l: *Lua) callconv(.c) i32 {
            l.pushLString("Reardon");
            return 1;
        }
    };

    try lua.doString(
        \\return function(lib)
        \\    john, hank = lib.john(), lib.hank()
        \\    if (john == 'Galt' and hank == 'Reardon') then
        \\        return 1
        \\    end
        \\    return 0
        \\end
    );

    lua.newTable();
    lua.registerLibrary(
        null,
        &[_]Lua.Reg{
            .{ .name = "john", .func = &T.john },
            .{ .name = "hank", .func = &T.hank },
            Lua.RegEnd,
        },
    );

    try lua.callProtected(1, 1, 0);
    try std.testing.expect(lua.isInteger(-1));
    try std.testing.expectEqual(1, lua.toIntegerStrict(-1));
}

test "threads should share global state and not share local state" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    lua.openBaseLib();

    lua.pushInteger(42);
    lua.setGlobal("test_global");

    const thread = lua.newThread();
    try std.testing.expect(lua != thread);
    try thread.doString("assert(test_global == 42)");

    lua.pushInteger(70);
    thread.pushInteger(100);

    try std.testing.expectEqual(70, try lua.toIntegerStrict(-1));
    try std.testing.expectEqual(100, try thread.toIntegerStrict(-1));
}

test "threads should have the identity property according to toThread()" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    const t1 = lua.newThread();
    const t2 = lua.newThread();
    try std.testing.expect(t1 != t2);

    const a1 = lua.toThread(-2);
    try std.testing.expect(a1 != null);

    const a2 = lua.toThread(-1);
    try std.testing.expect(a2 != null);

    try std.testing.expect(a1 != a2);
}

test "toThread() should return null for unsupported types" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    lua.pushInteger(42);
    try std.testing.expect(lua.toThread(-1) == null);
    lua.pop(1);

    lua.pushNil();
    try std.testing.expect(lua.toThread(-1) == null);
    lua.pop(1);

    lua.pushBoolean(false);
    try std.testing.expect(lua.toThread(-1) == null);
    lua.pop(1);
}

test "newUserdata should create expected memory" {
    const lua = try Lua.init(std.testing.allocator);
    defer {
        lua.deinit();
    }
    const ud = lua.newUserdata(@sizeOf(u32));
    const found = lua.toUserdata(-1);

    try std.testing.expectEqual(ud, found);
}

test "pushThread should return whether it is running on the main thread or not" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    try std.testing.expect(lua.pushThread());
    try std.testing.expectEqual(Lua.Type.thread, lua.getType(-1));
    lua.pop(1);

    const coroutine = lua.newThread();
    try std.testing.expect(!coroutine.pushThread());
    try std.testing.expectEqual(Lua.Type.thread, lua.getType(-1));
    lua.pop(1);
}

test "setEnvironment and getEnvironment should return false when target does not support environment" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    lua.pushNumber(1.23);
    lua.newTable();
    try std.testing.expect(!lua.setEnvironment(-2));
    try std.testing.expectEqual(1, lua.getTop());
    lua.pop(1);

    lua.newTable();
    lua.newTable();
    try std.testing.expect(!lua.setEnvironment(-2));
    try std.testing.expectEqual(1, lua.getTop());
    lua.pop(1);

    lua.pushLString("string does not support environment");
    lua.newTable();
    try std.testing.expect(!lua.setEnvironment(-2));
    try std.testing.expectEqual(1, lua.getTop());
    lua.pop(1);

    lua.pushNil();
    lua.newTable();
    try std.testing.expect(!lua.setEnvironment(-2));
    try std.testing.expectEqual(1, lua.getTop());
    lua.pop(1);

    lua.pushBoolean(false);
    lua.newTable();
    try std.testing.expect(!lua.setEnvironment(-2));
    try std.testing.expectEqual(1, lua.getTop());
    lua.pop(1);
}

test "setEnvironment and getEnvironment should work for thread" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    _ = lua.newThread();
    lua.newTable();
    lua.pushLString("bar");
    lua.setField(-2, "foo");

    try std.testing.expect(lua.setEnvironment(-2));
    try std.testing.expectEqual(1, lua.getTop());
    try std.testing.expect(lua.isThread(-1));
    lua.getEnvironment(-1);
    try std.testing.expect(lua.isTable(-1));
    const actual_type = lua.getField(-1, "foo");
    try std.testing.expectEqual(Lua.Type.string, actual_type);
    lua.pushLString("bar");
    try std.testing.expect(lua.equal(-1, -2));
    try std.testing.expectEqual(4, lua.getTop());
    lua.pop(4);
}

test "setEnvironment and getEnvironment should work for functions" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    lua.openBaseLib();

    try lua.doString(
        \\ x = function()
        \\     print("Test")
        \\ end
        \\ return x
    );
    lua.newTable();
    lua.pushLString("bar");
    lua.setField(-2, "foo");

    try std.testing.expect(lua.setEnvironment(-2));
    try std.testing.expectEqual(1, lua.getTop());
    try std.testing.expect(lua.isFunction(-1));
    lua.getEnvironment(-1);
    try std.testing.expect(lua.isTable(-1));
    const actual_type = lua.getField(-1, "foo");
    try std.testing.expectEqual(Lua.Type.string, actual_type);
    lua.pushLString("bar");
    try std.testing.expect(lua.equal(-1, -2));
    try std.testing.expectEqual(4, lua.getTop());
    lua.pop(4);
}

test "setEnvironment and getEnvironment should work for userdata" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    _ = lua.newUserdata(1);
    lua.newTable();
    lua.pushLString("bar");
    lua.setField(-2, "foo");

    try std.testing.expect(lua.setEnvironment(-2));
    try std.testing.expectEqual(1, lua.getTop());
    try std.testing.expect(lua.isUserdata(-1));
    lua.getEnvironment(-1);
    try std.testing.expect(lua.isTable(-1));
    const actual_type = lua.getField(-1, "foo");
    try std.testing.expectEqual(Lua.Type.string, actual_type);
    lua.pushLString("bar");
    try std.testing.expect(lua.equal(-1, -2));
    try std.testing.expectEqual(4, lua.getTop());
    lua.pop(4);
}

test "toCFunction should return null for non-cfunction types" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    lua.pushInteger(42);
    try std.testing.expect(lua.toCFunction(-1) == null);
    lua.pop(1);

    lua.pushNil();
    try std.testing.expect(lua.toCFunction(-1) == null);
    lua.pop(1);

    lua.pushBoolean(false);
    try std.testing.expect(lua.toCFunction(-1) == null);
    lua.pop(1);

    lua.pushLString("ASDF");
    try std.testing.expect(lua.toCFunction(-1) == null);
    lua.pop(1);

    lua.newTable();
    try std.testing.expect(lua.toCFunction(-1) == null);
    lua.pop(1);
}

test "toCFunction should return expected function" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    const T = struct {
        fn registeredFn(l: *Lua) callconv(.c) i32 {
            l.pushLString("Galt, John");
            return 1;
        }
    };

    lua.pushCFunction(T.registeredFn);
    const actual = lua.toCFunction(-1);
    try std.testing.expect(actual != null);
    try std.testing.expectEqual(T.registeredFn, actual);
    lua.pop(1);
}

test "toPointer should return null for unsupported types" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    lua.pushInteger(42);
    try std.testing.expect(lua.toPointer(-1) == null);
    lua.pop(1);

    lua.pushNil();
    try std.testing.expect(lua.toPointer(-1) == null);
    lua.pop(1);

    lua.pushBoolean(false);
    try std.testing.expect(lua.toPointer(-1) == null);
    lua.pop(1);
}

test "toPointer should return a non-null pointer for supported types" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    const T = struct {
        fn registeredFn(l: *Lua) callconv(.c) i32 {
            l.pushLString("Galt, John");
            return 1;
        }
    };

    lua.pushLString("ASDF");
    try std.testing.expect(lua.toPointer(-1) != null);
    lua.pop(1);

    lua.newTable();
    try std.testing.expect(lua.toPointer(-1) != null);
    lua.pop(1);

    lua.pushCFunction(T.registeredFn);
    try std.testing.expect(lua.toPointer(-1) != null);
    lua.pop(1);

    const ud = lua.newUserdata(1);
    try std.testing.expect(lua.toPointer(-1) != null);
    try std.testing.expectEqual(ud, lua.toPointer(-1));
    lua.pop(1);
}

test "xmove should migrate values from one thread to another" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    const t1 = lua.newThread();
    const t2 = lua.newThread();

    t1.pushInteger(42);
    t2.pushInteger(42);
    // Use method syntax
    t1.xmove(t2, 1);

    try std.testing.expectEqual(0, t1.getTop());
    try std.testing.expectEqual(2, t2.getTop());
    try std.testing.expect(t2.equal(-1, -2));

    // Or use function syntax
    Lua.xmove(t2, t1, 1);
    try std.testing.expectEqual(1, t1.getTop());
    try std.testing.expectEqual(1, t2.getTop());
}

test "checkInteger should return given value or raise an error" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    const T = struct {
        fn EchoInteger(l: *Lua) callconv(.c) i32 {
            const val = l.checkInteger(1);
            l.pushInteger(val);
            return 1;
        }
    };

    const expected: Lua.Integer = 42;
    lua.pushCFunction(T.EchoInteger);
    lua.pushInteger(expected);
    try lua.callProtected(1, 1, 0);
    try std.testing.expectEqual(expected, lua.toInteger(-1));
    lua.pop(1);

    lua.pushCFunction(T.EchoInteger);
    lua.pushNumber(42.444);
    try lua.callProtected(1, 1, 0);
    try std.testing.expectEqual(expected, lua.toInteger(-1));
    lua.pop(1);

    lua.pushCFunction(T.EchoInteger);
    lua.pushString("NotANumber");
    const actual = lua.callProtected(1, 1, 0);
    try std.testing.expectError(error.Runtime, actual);
    try std.testing.expectEqualSlices(u8, "bad argument #1 to '?' (number expected, got string)", try lua.toLString(-1));
}

test "checkIntegerOptional should return given value, default or raise an error" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    const default: Lua.Integer = 42;
    const T = struct {
        fn EchoIntegerOptional(l: *Lua) callconv(.c) i32 {
            const val = l.checkIntegerOptional(1, default);
            l.pushInteger(val);
            return 1;
        }
    };

    const expected: Lua.Integer = 33;
    lua.pushCFunction(T.EchoIntegerOptional);
    lua.pushInteger(expected);
    try lua.callProtected(1, 1, 0);
    try std.testing.expectEqual(expected, lua.toInteger(-1));
    lua.pop(1);

    lua.pushCFunction(T.EchoIntegerOptional);
    lua.pushNumber(33.444);
    try lua.callProtected(1, 1, 0);
    try std.testing.expectEqual(expected, lua.toInteger(-1));
    lua.pop(1);

    lua.pushCFunction(T.EchoIntegerOptional);
    try lua.callProtected(0, 1, 0);
    try std.testing.expectEqual(default, lua.toInteger(-1));
    lua.pop(1);

    lua.pushCFunction(T.EchoIntegerOptional);
    lua.pushString("NotANumber");
    const actual = lua.callProtected(1, 1, 0);
    try std.testing.expectError(error.Runtime, actual);
    try std.testing.expectEqualSlices(u8, "bad argument #1 to '?' (number expected, got string)", try lua.toLString(-1));
}

test "checkNumber should return given value or raise an error" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    const T = struct {
        fn Echo(l: *Lua) callconv(.c) i32 {
            const val = l.checkNumber(1);
            l.pushNumber(val);
            return 1;
        }
    };

    const expected: Lua.Number = 42.720;
    lua.pushCFunction(T.Echo);
    lua.pushNumber(expected);
    try lua.callProtected(1, 1, 0);
    try std.testing.expectEqual(expected, lua.toNumber(1));
    lua.pop(1);

    lua.pushCFunction(T.Echo);
    lua.pushString("NotANumber");
    const actual = lua.callProtected(1, 1, 0);
    try std.testing.expectError(error.Runtime, actual);
    try std.testing.expectEqualSlices(u8, "bad argument #1 to '?' (number expected, got string)", try lua.toLString(-1));
}

test "checkNumberOptional should return given value or raise an error" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    const T = struct {
        fn Echo(l: *Lua) callconv(.c) i32 {
            const val = l.checkNumberOptional(1, 13.33);
            l.pushNumber(val);
            return 1;
        }
    };

    const expected: Lua.Number = 42.720;
    lua.pushCFunction(T.Echo);
    lua.pushNumber(expected);
    try lua.callProtected(1, 1, 0);
    try std.testing.expectEqual(expected, lua.toNumber(-1));
    lua.pop(1);

    lua.pushCFunction(T.Echo);
    try lua.callProtected(0, 1, 0);
    try std.testing.expectEqual(13.33, lua.toNumber(-1));
    lua.pop(1);

    lua.pushCFunction(T.Echo);
    lua.pushString("NotANumber");
    const actual = lua.callProtected(1, 1, 0);
    try std.testing.expectError(error.Runtime, actual);
    try std.testing.expectEqualSlices(u8, "bad argument #1 to '?' (number expected, got string)", try lua.toLString(-1));
}

test "checkString() should validate presence of arguments and return the correct value" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    const T = struct {
        fn EchoString(l: *Lua) callconv(.c) i32 {
            const actual = l.checkString(1);
            l.pushString(actual);
            return 1;
        }
    };

    const expected = "Who is John Galt?";
    lua.pushCFunction(T.EchoString);
    lua.pushString(expected);
    try lua.callProtected(1, 1, 0);
    const a1 = try lua.toLString(-1);
    try std.testing.expectEqualSlices(u8, expected, a1);
    lua.pop(1);

    lua.pushCFunction(T.EchoString);
    const a2 = lua.callProtected(0, 1, 0);
    try std.testing.expectError(error.Runtime, a2);
    try std.testing.expectEqualStrings("bad argument #1 to '?' (string expected, got no value)", try lua.toLString(-1));

    lua.pushCFunction(T.EchoString);
    lua.pushInteger(42);
    try lua.callProtected(1, 1, 0);
    const a3 = try lua.toLString(-1);
    try std.testing.expectEqualStrings("42", a3);
    lua.pop(1);
}

test "checkStringOptional() should validate presence of arguments and return the correct value" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    const T = struct {
        fn EchoString(l: *Lua) callconv(.c) i32 {
            const actual = l.checkStringOptional(1, "FOO");
            l.pushString(actual);
            return 1;
        }
    };

    const expected = "Who is John Galt?";
    lua.pushCFunction(T.EchoString);
    lua.pushString(expected);
    try lua.callProtected(1, 1, 0);
    const a1 = try lua.toLString(-1);
    try std.testing.expectEqualSlices(u8, expected, a1);
    lua.pop(1);

    lua.pushCFunction(T.EchoString);
    try lua.callProtected(0, 1, 0);
    try std.testing.expectEqualSlices(u8, "FOO", (try lua.toString(-1))[0..3 :0]);

    lua.pushCFunction(T.EchoString);
    lua.pushInteger(42);
    try lua.callProtected(1, 1, 0);
    const a3 = try lua.toLString(-1);
    try std.testing.expectEqualStrings("42", a3);
    lua.pop(1);
}

test "checkLString() should validate presence of arguments and return the correct value" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    const T = struct {
        fn EchoString(l: *Lua) callconv(.c) i32 {
            const actual = l.checkLString(1);
            l.pushLString(actual);
            return 1;
        }
    };

    const expected = "Who is John Galt?";
    lua.pushCFunction(T.EchoString);
    lua.pushLString(expected);
    try lua.callProtected(1, 1, 0);
    const a1 = try lua.toLString(-1);
    try std.testing.expectEqualSlices(u8, expected, a1);
    lua.pop(1);

    lua.pushCFunction(T.EchoString);
    const a2 = lua.callProtected(0, 1, 0);
    try std.testing.expectError(error.Runtime, a2);
    try std.testing.expectEqualSlices(u8, "bad argument #1 to '?' (string expected, got no value)", try lua.toLString(-1));

    lua.pushCFunction(T.EchoString);
    lua.pushInteger(42);
    try lua.callProtected(1, 1, 0);
    const a3 = try lua.toLString(-1);
    try std.testing.expectEqualSlices(u8, "42", a3);
    lua.pop(1);
}

test "checkLStringOptional() should validate presence of arguments and return the correct value" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    const T = struct {
        fn EchoString(l: *Lua) callconv(.c) i32 {
            const actual = l.checkLStringOptional(1, "FOO");
            l.pushLString(actual);
            return 1;
        }
    };

    const expected = "Who is John Galt?";
    lua.pushCFunction(T.EchoString);
    lua.pushLString(expected);
    try lua.callProtected(1, 1, 0);
    const a1 = try lua.toLString(-1);
    try std.testing.expectEqualSlices(u8, expected, a1);
    lua.pop(1);

    lua.pushCFunction(T.EchoString);
    try lua.callProtected(0, 1, 0);
    try std.testing.expectEqualSlices(u8, "FOO", try lua.toLString(-1));

    lua.pushCFunction(T.EchoString);
    lua.pushInteger(42);
    try lua.callProtected(1, 1, 0);
    const a3 = try lua.toLString(-1);
    try std.testing.expectEqualSlices(u8, "42", a3);
    lua.pop(1);
}

test "checkAny should validate presence of arguments" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    const T = struct {
        fn Fn(l: *Lua) callconv(.c) i32 {
            l.checkAny(1);
            return 0;
        }
    };

    lua.pushCFunction(T.Fn);
    lua.pushBoolean(true);
    try lua.callProtected(1, 0, 0);
    try std.testing.expectEqual(0, lua.getTop());

    lua.pushCFunction(T.Fn);
    const actual = lua.callProtected(0, 0, 0);
    try std.testing.expectError(error.Runtime, actual);
    try std.testing.expectEqualSlices(u8, "bad argument #1 to '?' (value expected)", try lua.toLString(-1));
}

test "checkOption() should validate arguments and use default" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    const T = struct {
        fn EchoStringWithDefault(l: *Lua) callconv(.c) i32 {
            const actual = l.checkOption(1, &.{ "A", "B", "C" }, "C");
            l.pushInteger(@intCast(actual));
            return 1;
        }
        fn EchoString(l: *Lua) callconv(.c) i32 {
            const actual = l.checkOption(1, &.{ "A", "B", "C" }, null);
            l.pushInteger(@intCast(actual));
            return 1;
        }
    };

    lua.pushCFunction(T.EchoStringWithDefault);
    try lua.callProtected(0, 1, 0);
    const a1 = try lua.toIntegerStrict(-1);
    try std.testing.expectEqual(2, a1); // The default value should find the match
    lua.pop(1);

    lua.pushCFunction(T.EchoString);
    const a2 = lua.callProtected(0, 1, 0);
    try std.testing.expectError(Lua.CallError.Runtime, a2); // No default value so the check should fail

    lua.pushCFunction(T.EchoString);
    lua.pushLString("C");
    try lua.callProtected(1, 1, 0);
    const a3 = try lua.toIntegerStrict(-1);
    try std.testing.expectEqual(2, a3); // The value should be found at the third index
}

test "checkType should validate argument type" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    const T = struct {
        fn Fn(l: *Lua) callconv(.c) i32 {
            l.checkType(1, .string);
            return 0;
        }
    };

    lua.pushCFunction(T.Fn);
    lua.pushLString("happy path");
    try lua.callProtected(1, 0, 0);
    try std.testing.expectEqual(0, lua.getTop());

    lua.pushCFunction(T.Fn);
    const a1 = lua.callProtected(0, 0, 0);
    try std.testing.expectError(error.Runtime, a1);
    try std.testing.expectEqualSlices(u8, "bad argument #1 to '?' (string expected, got no value)", try lua.toLString(-1));

    lua.pushCFunction(T.Fn);
    lua.pushInteger(42);
    const a2 = lua.callProtected(1, 0, 0);
    try std.testing.expectError(error.Runtime, a2);
    try std.testing.expectEqualSlices(u8, "bad argument #1 to '?' (string expected, got number)", try lua.toLString(-1));
}

test "checkArgument() should return error when argument is invalid and succeed when argument is OK" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    const T = struct {
        fn EchoInteger(l: *Lua) callconv(.c) i32 {
            const val = l.toInteger(1);
            l.checkArgument(val != 42, 1, "FOOBAR");
            l.pushInteger(val);
            return 1;
        }
    };

    lua.pushCFunction(T.EchoInteger);
    lua.pushInteger(42);
    try lua.callProtected(1, 1, 0);
    try std.testing.expectEqual(42, lua.toInteger(1));
    lua.pop(1);

    lua.pushCFunction(T.EchoInteger);
    lua.pushInteger(1);
    const actual = lua.callProtected(1, 1, 0);
    try std.testing.expectError(error.Runtime, actual);

    const message = try lua.toLString(-1);
    try std.testing.expectEqualSlices(u8, "bad argument #1 to '?' (FOOBAR)", message);
}

test "checkUserdata() will accept user data with the correct metatable type" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    const T = struct {
        fn EchoUserdata(l: *Lua) callconv(.c) i32 {
            const val = l.checkUserdata(1, "MyUserdataType");
            l.pushLightUserdata(val);
            return 1;
        }
    };

    lua.pushCFunction(T.EchoUserdata);

    const expected = lua.newUserdata(32);
    try std.testing.expect(lua.newMetatable("MyUserdataType"));
    lua.setMetatable(-2);
    try std.testing.expectEqual(2, lua.getTop());
    try std.testing.expect(lua.isFunction(1));
    try std.testing.expect(lua.isUserdata(2));

    try lua.callProtected(1, 1, 0);

    try std.testing.expectEqual(1, lua.getTop());
    try std.testing.expect(lua.isUserdata(-1));
    try std.testing.expectEqual(expected, lua.toUserdata(-1));
}

test "checkUserdata() will reject user data with the wrong metatable type" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    const T = struct {
        fn EchoUserdata(l: *Lua) callconv(.c) i32 {
            const val = l.checkUserdata(1, "MyUserdataType");
            l.pushLightUserdata(val);
            return 1;
        }
    };

    lua.pushCFunction(T.EchoUserdata);

    _ = lua.newUserdata(32);
    try std.testing.expectEqual(2, lua.getTop());
    try std.testing.expect(lua.isFunction(1));
    try std.testing.expect(lua.isUserdata(2));

    try std.testing.expectError(error.Runtime, lua.callProtected(1, 1, 0));
    try std.testing.expectEqualStrings("bad argument #1 to '?' (MyUserdataType expected, got userdata)", try lua.toLString(-1));
}

test "checkArgument() should return handle null message" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    const T = struct {
        fn EchoInteger(l: *Lua) callconv(.c) i32 {
            const val = l.toInteger(1);
            l.checkArgument(val != 42, 1, null);
            l.pushInteger(val);
            return 1;
        }
    };

    lua.pushCFunction(T.EchoInteger);
    lua.pushInteger(1);
    const actual = lua.callProtected(1, 1, 0);
    try std.testing.expectError(error.Runtime, actual);

    const message = try lua.toLString(-1);
    try std.testing.expectEqualSlices(u8, "bad argument #1 to '?' ((null))", message);
}

test "raiseErrorArgument() should return correct error messages" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    const T = struct {
        fn FullError(l: *Lua) callconv(.c) i32 {
            return l.raiseErrorArgument(1, "FOO");
        }
        fn NullError(l: *Lua) callconv(.c) i32 {
            return l.raiseErrorArgument(1, null);
        }
    };

    lua.pushCFunction(T.FullError);
    lua.pushInteger(1);
    try std.testing.expectError(error.Runtime, lua.callProtected(1, 1, 0));
    try std.testing.expectEqualSlices(u8, "bad argument #1 to '?' (FOO)", try lua.toLString(-1));

    lua.pushCFunction(T.NullError);
    lua.pushInteger(1);
    try std.testing.expectError(error.Runtime, lua.callProtected(1, 1, 0));
    try std.testing.expectEqualSlices(u8, "bad argument #1 to '?' ((null))", try lua.toLString(-1));
}

test "raiseErrorType() should return correct error messages" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    const T = struct {
        fn FullError(l: *Lua) callconv(.c) i32 {
            return l.raiseErrorType(1, "FOO");
        }
        fn NullError(l: *Lua) callconv(.c) i32 {
            return l.raiseErrorType(1, null);
        }
    };

    lua.pushCFunction(T.FullError);
    lua.pushInteger(1);
    try std.testing.expectError(error.Runtime, lua.callProtected(1, 1, 0));
    try std.testing.expectEqualSlices(u8, "bad argument #1 to '?' (FOO expected, got number)", try lua.toLString(-1));

    lua.pushCFunction(T.NullError);
    lua.pushInteger(1);
    try std.testing.expectError(error.Runtime, lua.callProtected(1, 1, 0));
    try std.testing.expectEqualSlices(u8, "bad argument #1 to '?' ((null) expected, got number)", try lua.toLString(-1));
}

test "where() should report correct location" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    const T = struct {
        fn whereFn(l: *Lua) callconv(.c) i32 {
            l.where(1);
            return 1;
        }
    };
    lua.registerFunction("whereFn", T.whereFn);
    try lua.doString("actual = whereFn()");

    try std.testing.expectEqual(Lua.Type.string, lua.getGlobal("actual"));
    try std.testing.expectEqual(1, lua.getTop());
    try std.testing.expectEqualStrings(
        "[string \"actual = whereFn()\"]:1: ",
        try lua.toLString(-1),
    );
}

test "ref and unref in user table" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    lua.newTable();
    lua.pushLString("foo");
    const ref = lua.ref(1);

    try std.testing.expectEqual(1, lua.getTop());
    try std.testing.expect(Lua.Ref.None != ref);
    try std.testing.expect(Lua.Ref.Nil != ref);

    const t = lua.getTableIndexRaw(1, ref);
    try std.testing.expectEqual(Lua.Type.string, t);

    lua.unref(1, ref);
    try std.testing.expectEqual(0, lua.getLength(1));
}

test "ref should return nil" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    lua.newTable();
    lua.pushNil();
    const ref = lua.ref(1);

    try std.testing.expectEqual(1, lua.getTop());
    try std.testing.expectEqual(Lua.Ref.Nil, ref);

    const t = lua.getTableIndexRaw(1, ref);
    try std.testing.expectEqual(Lua.Type.nil, t);
    try std.testing.expect(lua.isNil(-1));

    lua.unref(1, ref);
    try std.testing.expectEqual(0, lua.getLength(1));
}

test "ref and unref in registry" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    lua.pushValue(Lua.PseudoIndex.Registry);
    const length_before = lua.getLength(1);
    lua.pop(1);

    lua.pushLString("foo");
    const ref = lua.ref(Lua.PseudoIndex.Registry);

    try std.testing.expectEqual(0, lua.getTop());
    try std.testing.expect(Lua.Ref.None != ref);
    try std.testing.expect(Lua.Ref.Nil != ref);

    const t = lua.getTableIndexRaw(Lua.PseudoIndex.Registry, ref);
    try std.testing.expectEqual(Lua.Type.string, t);
    try std.testing.expectEqualStrings("foo", try lua.toLString(-1));
    lua.pop(1);

    lua.unref(Lua.PseudoIndex.Registry, ref);
    lua.pushValue(Lua.PseudoIndex.Registry);
    try std.testing.expectEqual(length_before, lua.getLength(1));
}

test "Lua functions can be serialized and restored using dump() and load()" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    var buf: [256]u8 = undefined;
    var fbs_write = std.io.fixedBufferStream(&buf);

    try lua.doString("return function(x) return x * 2 end");
    try std.testing.expectEqual(1, lua.getTop()); // The stack should contain one value, a function.
    try lua.dump(fbs_write.writer().any());

    lua.pop(1);
    try std.testing.expectEqual(0, lua.getTop()); // The stack should be empty, ensuring that the function is fully restored from the binary chunk.

    var fbs_read = std.io.fixedBufferStream(fbs_write.getWritten());
    try lua.load(fbs_read.reader().any(), null);

    lua.pushInteger(21);
    try lua.callProtected(1, 1, 0);
    try std.testing.expectEqual(42, try lua.toIntegerStrict(-1)); // The function should be the "multiply by two" function from above.
}

test "loadBuffer can load binary content including null bytes" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    // Equivalent to the load binary content from disk test, notice there are null bytes wtihin the string, particularly in the bytecode.
    // 00000000  1b 4c 4a 02 08 23 72 65  74 75 72 6e 20 66 75 6e  |.LJ..#return fun|
    // 00000010  63 74 69 6f 6e 28 78 29  20 72 65 74 75 72 6e 20  |ction(x) return |
    // 00000020  78 20 2a 20 32 20 65 6e  64 1a 00 01 02 00 00 01  |x * 2 end.......|
    // 00000030  02 07 01 00 18 01 00 00  4c 01 02 00 04 00 00 78  |........L......x|
    // 00000040  00 00 03 00 00                                    |.....|
    const binary = "\x1b\x4c\x4a\x02\x08\x23\x72\x65\x74\x75\x72\x6e\x20\x66\x75\x6e\x63\x74\x69\x6f\x6e\x28\x78\x29\x20\x72\x65\x74\x75\x72\x6e\x20\x78\x20\x2a\x20\x32\x20\x65\x6e\x64\x1a\x00\x01\x02\x00\x00\x01\x02\x07\x01\x00\x18\x01\x00\x00\x4c\x01\x02\x00\x04\x00\x00\x78\x00\x00\x03\x00\x00";
    try lua.loadBuffer(binary, "my-test-chunk");
    try std.testing.expectEqual(Lua.Type.function, lua.getType(-1));
    lua.pushInteger(21);
    try lua.callProtected(1, 1, 0);
    try std.testing.expect(lua.isInteger(-1));
    try std.testing.expectEqual(42, lua.toIntegerStrict(-1));
}

test "Lua functions can be run from files with Lua source code" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    lua.openLibs();

    const dir_name = try std.fs.getAppDataDir(std.testing.allocator, "zig-luajit-tests");
    defer std.testing.allocator.free(dir_name);
    var dir = try std.fs.cwd().makeOpenPath(dir_name, .{});
    defer dir.close();
    var f = try dir.createFile("test-dofile-source-code-from-file", .{});

    var path_buffer: [std.fs.max_path_bytes + 1]u8 = undefined;
    const full_path = try std.os.getFdPath(f.handle, path_buffer[0..std.fs.max_path_bytes]);
    path_buffer[full_path.len] = 0;
    const full_path_sentinel = path_buffer[0..full_path.len :0];
    try f.writeAll(
        \\ return function(x)
        \\     return x * 2
        \\ end
        \\
    );
    f.close();

    try std.testing.expectEqual(0, lua.getTop()); // The stack should be empty, ensuring that the function is fully restored from the binary chunk.

    try lua.doFile(full_path_sentinel);
    try std.testing.expectEqual(Lua.Type.function, lua.getType(-1));

    lua.pushInteger(21);
    try lua.callProtected(1, 1, 0);
    try std.testing.expect(lua.isInteger(-1));
    try std.testing.expectEqual(42, lua.toIntegerStrict(-1));
}

test "loadFile should return error when file does not exist" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    const actual = lua.loadFile("some_random_file_that_definitely_does_not_exist_2093u102894u12804u12894u12894u1");
    try std.testing.expectError(Lua.LoadFileError.FileOpenOrFileRead, actual);
}

test "Lua functions can be loaded as Lua source code from a file" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    lua.openLibs();

    const dir_name = try std.fs.getAppDataDir(std.testing.allocator, "zig-luajit-tests");
    defer std.testing.allocator.free(dir_name);
    var dir = try std.fs.cwd().makeOpenPath(dir_name, .{});
    defer dir.close();
    var f = try dir.createFile("test-load-source-code-from-file", .{});

    var path_buffer: [std.fs.max_path_bytes + 1]u8 = undefined;
    const full_path = try std.os.getFdPath(f.handle, path_buffer[0..std.fs.max_path_bytes]);
    path_buffer[full_path.len] = 0;
    const full_path_sentinel = path_buffer[0..full_path.len :0];
    try f.writeAll(
        \\ function foo(x)
        \\     assert(x == 21)
        \\ end
        \\
    );
    f.close();

    try std.testing.expectEqual(0, lua.getTop()); // The stack should be empty, ensuring that the function is fully restored from the binary chunk.

    try lua.loadFile(full_path_sentinel);
    try std.testing.expectEqual(Lua.Type.function, lua.getType(-1));

    lua.pushInteger(21);
    try lua.callProtected(1, 1, 0); // Assertion should pass
}

test "Lua functions can be loaded as Lua byte code (binary) from a file" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    var buf: [256]u8 = undefined;
    var fbs_write = std.io.fixedBufferStream(&buf);

    try lua.doString("return function(x) return x * 2 end");
    try std.testing.expectEqual(1, lua.getTop()); // The stack should contain one value, a function.
    try lua.dump(fbs_write.writer().any());
    const result = fbs_write.getWritten();

    const dir_name = try std.fs.getAppDataDir(std.testing.allocator, "zig-luajit-tests");
    defer std.testing.allocator.free(dir_name);
    var dir = try std.fs.cwd().makeOpenPath(dir_name, .{});
    defer dir.close();
    var f = try dir.createFile("test-load-binary-from-file", .{});

    var path_buffer: [std.fs.max_path_bytes + 1]u8 = undefined;
    const full_path = try std.os.getFdPath(f.handle, path_buffer[0..std.fs.max_path_bytes]);
    path_buffer[full_path.len] = 0;
    const full_path_sentinel = path_buffer[0..full_path.len :0];

    try f.writeAll(result);
    f.close();

    lua.pop(1);
    try std.testing.expectEqual(0, lua.getTop()); // The stack should be empty, ensuring that the function is fully restored from the binary chunk.

    try lua.loadFile(full_path_sentinel);

    lua.pushInteger(21);
    try lua.callProtected(1, 1, 0);
    try std.testing.expectEqual(42, try lua.toIntegerStrict(-1)); // The function should be the "multiply by two" function from above.
}

test "dump() should report the same errors returned by the AnyWriter" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    var buf: [16]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);

    try lua.doString("return function(x) return x * 2 end");
    const actual = lua.dump(fbs.writer().any());
    try std.testing.expectError(error.NoSpaceLeft, actual);
}

test "load() should report syntax errors when loading invalid binary chunk" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    var buf: [3]u8 = .{ 0, 0, 0 };
    var fbs = std.io.fixedBufferStream(&buf);

    const actual = lua.load(fbs.reader().any(), null);
    try std.testing.expectError(error.InvalidSyntax, actual);
}

test "load() should report runtime errors when reading fails" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    const ErrRead = struct {
        fn errRead(context: *const anyopaque, buffer: []u8) anyerror!usize {
            _ = context;
            _ = buffer;
            return error.TestingError;
        }
    };

    const err_reader = std.io.AnyReader{
        .context = @ptrCast(&lua),
        .readFn = &ErrRead.errRead,
    };

    const actual = lua.load(err_reader, null);
    try std.testing.expectError(Lua.LoadError.Runtime, actual);
    try std.testing.expectEqualStrings("Unable to load function, found error 'TestingError' while reading.", try lua.toLString(-1));
}

test "suspend and resume coroutines" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    const T = struct {
        fn asyncFn(l: *Lua) callconv(.c) i32 {
            l.pushInteger(10);
            if (1 == 1) return l.yieldCoroutine(1);

            l.pushInteger(20);
            return 1;
        }
    };

    const thread = lua.newThread();

    thread.pushCFunction(T.asyncFn);
    const s1 = thread.resumeCoroutine(0);
    try std.testing.expectEqual(Lua.Status.yield, s1);
    try std.testing.expectEqual(10, try thread.toIntegerStrict(-1));

    const s2 = thread.resumeCoroutine(0);
    try std.testing.expectEqual(Lua.Status.ok, s2);

    // TODO: This does not return the expected behavior - I do not think yield and resume work as expected.
    // try std.testing.expectEqual(20, try thread.toIntegerStrict(-1));
}

test "gsub" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    const string = "ABBA";
    const pattern = "B";
    const replacement = "C";
    const expected = "ACCA";

    const actual = lua.gsub(string, pattern, replacement);

    try std.testing.expectEqual(1, lua.getTop());
    try std.testing.expectEqualStrings(expected, try lua.toLString(-1));
    try std.testing.expectEqualStrings(expected, actual);
}

test "metatables in the registry" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    try std.testing.expect(lua.newMetatable("test"));
    lua.pushInteger(42);
    lua.setField(-2, "bar");
    try std.testing.expect(!lua.newMetatable("test"));

    try std.testing.expectEqual(2, lua.getTop());
    try std.testing.expectEqual(lua.toPointer(-1), lua.toPointer(-2));
    lua.pop(1);

    lua.getMetatableRegistry("test");
    try std.testing.expectEqual(2, lua.getTop());
    try std.testing.expectEqual(lua.toPointer(-1), lua.toPointer(-2));
    lua.pop(1);

    lua.newTable();
    lua.insert(-2);
    lua.setMetatable(-2);
    try std.testing.expectEqual(1, lua.getTop());

    try std.testing.expect(lua.getMetaField(-1, "bar"));
    try std.testing.expectEqual(42, try lua.toIntegerStrict(-1));
}

test "callMeta() should invoke metamethod when it is defined" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    lua.openBaseLib();

    try lua.doString(
        \\f = {}
        \\return setmetatable(f, {
        \\    __len = function (op)
        \\        return -1
        \\    end
        \\})
    );
    try std.testing.expect(lua.isTable(-1));
    try std.testing.expect(lua.callMeta(-1, "__len"));
    try std.testing.expect(lua.isInteger(-1));
    try std.testing.expectEqual(-1, try lua.toIntegerStrict(-1));
}

test "callMeta() should do nothing when it is not defined" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    lua.openBaseLib();

    try lua.doString(
        \\f = {}
        \\return f
    );
    try std.testing.expect(lua.isTable(-1));
    try std.testing.expect(!lua.callMeta(-1, "__len"));
    try std.testing.expect(lua.isTable(-1));
    try std.testing.expectEqual(1, lua.getTop());
}

test "Buffer should be able to build character by character" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    var b: Lua.Buffer = .{};
    lua.initBuffer(&b);
    b.addChar('H');
    b.addChar('e');
    b.addChar('l');
    b.addChar('l');
    b.addChar('o');
    b.addChar(',');
    b.addChar(' ');
    b.addChar('w');
    b.addChar('o');
    b.addChar('r');
    b.addChar('l');
    b.addChar('d');
    b.addChar('!');
    b.pushResult();

    try std.testing.expectEqual(1, lua.getTop());
    try std.testing.expect(lua.isString(-1));
    try std.testing.expectEqualStrings("Hello, world!", try lua.toLString(-1));
}

test "Buffer should handle very long string" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    var b: Lua.Buffer = .{};
    lua.initBuffer(&b);
    for (0..256_000) |i| {
        b.addChar('0' + @as(u8, @intCast((i % 10))));
    }
    b.pushResult();

    try std.testing.expectEqual(1, lua.getTop());
    try std.testing.expect(lua.isString(-1));
    try std.testing.expectEqualStrings("0123456789" ** 25_600, try lua.toLString(-1));
}

test "Buffer can be created by direct writes to the buffer" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    var b: Lua.Buffer = .{};
    lua.initBuffer(&b);
    var p = b.prepBuffer();
    p[0] = 'H';
    p += 1;
    p[0] = 'e';
    p += 1;
    p[0] = 'l';
    p += 1;
    p[0] = 'l';
    p += 1;
    p[0] = 'o';
    p += 1;
    b.addSize(5);
    b.pushResult();

    try std.testing.expectEqual(1, lua.getTop());
    try std.testing.expect(lua.isString(-1));
    try std.testing.expectEqualStrings("Hello", try lua.toLString(-1));
}

test "Buffer can be created by adding strings to the buffer" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    var b: Lua.Buffer = .{};
    lua.initBuffer(&b);
    b.addString("Hello, world!");
    b.pushResult();

    try std.testing.expectEqual(1, lua.getTop());
    try std.testing.expect(lua.isString(-1));
    try std.testing.expectEqualStrings("Hello, world!", try lua.toLString(-1));
}

test "Buffer can be created by adding literal strings to the buffer" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    var b: Lua.Buffer = .{};
    lua.initBuffer(&b);
    b.addLString("Hello, world!");
    b.pushResult();

    try std.testing.expectEqual(1, lua.getTop());
    try std.testing.expect(lua.isString(-1));
    try std.testing.expectEqualStrings("Hello, world!", try lua.toLString(-1));
}

test "Buffer can be created by adding values on the stack to the buffer" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    var b: Lua.Buffer = .{};
    lua.initBuffer(&b);

    lua.pushInteger(42);
    b.addValue();
    try std.testing.expectEqual(0, lua.getTop());

    lua.pushLString("AAA");
    b.addValue();
    try std.testing.expectEqual(0, lua.getTop());

    lua.pushNumber(99.2);
    b.addValue();
    try std.testing.expectEqual(0, lua.getTop());

    b.pushResult();

    try std.testing.expectEqual(1, lua.getTop());
    try std.testing.expect(lua.isString(-1));
    try std.testing.expectEqualStrings("42AAA99.2", try lua.toLString(-1));
}

test "getInfo() can be used to show debug information about a function" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    const expected_source =
        \\function foo(x)
        \\  return x * 2
        \\end
    ;
    try lua.doString(expected_source);
    try std.testing.expectEqual(Lua.Type.function, lua.getGlobal("foo"));

    var info: Lua.DebugInfo = .{};
    try std.testing.expect(lua.getInfo(">Su", &info));
    try std.testing.expectEqual(0, lua.getTop());

    try std.testing.expect(info.source != null);
    try std.testing.expectEqualSentinel(u8, 0, expected_source, info.source.?[0..std.mem.indexOfSentinel(u8, 0, info.source.?) :0]);
    try std.testing.expect(info.what != null);
    try std.testing.expectEqualStrings("Lua\x00", info.what.?[0..4]);
    try std.testing.expectEqual(0, info.short_src[29]);
    try std.testing.expectEqualStrings("[string \"function foo(x)...\"]\x00", info.short_src[0..30]);
    try std.testing.expectEqual(1, info.linedefined);
    try std.testing.expectEqual(3, info.lastlinedefined);
}

test "getInfo() can debug info can be pretty printed" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    const expected_source =
        \\function foo(x)
        \\  return x * 2
        \\end
    ;
    try lua.doString(expected_source);
    try std.testing.expectEqual(Lua.Type.function, lua.getGlobal("foo"));

    var info: Lua.DebugInfo = .{};
    try std.testing.expect(lua.getInfo(">Su", &info));
    try std.testing.expectEqual(0, lua.getTop());

    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try info.prettyPrint(fbs.writer().any());

    const actual = fbs.getWritten();
    try std.testing.expectEqual(279, actual.len);

    // The output contains a pointer address too, so we will match the two parts around that.
    try std.testing.expectEqualStrings(
        \\root.Lua.DebugInfo@
    , actual[0..19]);

    try std.testing.expectEqualStrings(
        \\ {
        \\  event: '?' (-1),
        \\  name: '<null>',
        \\  namewhat: '<null>',
        \\  what: 'Lua',
        \\  short_src: `[string "function foo(x)..."]`,
        \\  currentline: -1,
        \\  nups: 0,
        \\  linedefined: 1,
        \\  lastlinedefined: 3,
        \\  source:
        \\```
        \\function foo(x)
        \\  return x * 2
        \\end
        \\```
        \\}
        \\
    , actual[31..]);
}

test "getInfoFunction() can be used to show debug information about a function" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    const expected_source =
        \\function foo(x)
        \\  return x * 2
        \\end
    ;
    try lua.doString(expected_source);
    try std.testing.expectEqual(Lua.Type.function, lua.getGlobal("foo"));

    const info = try lua.getInfoFunction();
    try std.testing.expectEqual(0, lua.getTop());

    try std.testing.expect(info.source != null);
    try std.testing.expectEqualSentinel(u8, 0, expected_source, info.source.?);
    try std.testing.expectEqual(.lua, info.what);
    try std.testing.expectEqual(0, info.short_src[29]);
    try std.testing.expectEqualStrings("[string \"function foo(x)...\"]\x00", info.short_src[0..30]);
    try std.testing.expectEqual(1, info.linedefined);
    try std.testing.expectEqual(3, info.lastlinedefined);
}

test "getInfoFunction() can pretty printed" {
    const lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    const expected_source =
        \\function foo(x)
        \\  return x * 2
        \\end
    ;
    try lua.doString(expected_source);
    try std.testing.expectEqual(Lua.Type.function, lua.getGlobal("foo"));

    var info = try lua.getInfoFunction();
    try std.testing.expectEqual(0, lua.getTop());

    var buf: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try info.prettyPrint(fbs.writer().any());

    const actual = fbs.getWritten();
    try std.testing.expectEqual(209, actual.len);

    // The output contains a pointer address too, so we will match the two parts around that.
    try std.testing.expectEqualStrings(
        \\root.Lua.DebugInfoFunction@
    , actual[0..27]);

    try std.testing.expectEqualStrings(
        \\ {
        \\  what: 'lua',
        \\  short_src: `[string "function foo(x)..."]`,
        \\  nups: 0,
        \\  linedefined: 1,
        \\  lastlinedefined: 3,
        \\  source:
        \\```
        \\function foo(x)
        \\  return x * 2
        \\end
        \\```
        \\}
        \\
    , actual[39..]);
}
