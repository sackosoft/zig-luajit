//! Copyright (c) 2024-2025 Theodore Sackos
//! SPDX-License-Identifier: AGPL-3.0-or-later

// This file contains brainstorming and draft translations of the C API to Lua.

/// Adds the character c to the given buffer.
///
/// From: `void luaL_addchar(luaL_Buffer *B, char c);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_addchar
/// Stack Behavior: `[-0, +0, m]`
pub fn addChar(buffer: *LuaBuffer, char: u8) void;

/// Adds the string pointed to by `s` with length `l` to the buffer `B`. The string may contain embedded zeros.
///
/// From: `void luaL_addlstring(luaL_Buffer *B, const char *s, size_t l);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_addlstring
/// Stack Behavior: `[-0, +0, m]`
pub fn addLString(buffer: *Buffer, s: [*]const u8, l: usize) void;

/// Adds to the buffer B a string of length n previously copied to the buffer area.
///
/// From: `void luaL_addsize(luaL_Buffer *B, size_t n);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_addsize
/// Stack Behavior: `[-0, +0, m]`
pub fn addSize(buffer: *Buffer, n: usize) void;

/// Adds the zero-terminated string pointed to by s to the buffer B.
/// The string may not contain embedded zeros.
///
/// From: `void luaL_addstring(luaL_Buffer *B, const char *s);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_addstring
/// Stack Behavior: `[-0, +0, m]`
pub fn addString(buffer: *Buffer, s: [*:0]const u8) void;

/// Adds the value at the top of the stack to the buffer B (see https://www.lua.org/manual/5.1/manual.html#luaL_Buffer).
/// Pops the value. This is the only function on string buffers that can (and must) be called with an extra 
/// element on the stack, which is the value to be added to the buffer.
///
/// From: `void luaL_addvalue(luaL_Buffer *B);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_addvalue
/// Stack Behavior: `[-1, +0, m]`
pub fn addValue(buffer: *Buffer) void;

/// Raises an error with the message "bad argument #narg to func (extramsg)". The function
/// func is retrieved from the call stack. This function never returns, but it is an idiom
/// to use it as a return statement.
///
/// From: `int luaL_argerror(lua_State *L, int narg, const char *extramsg);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_argerror
/// Stack Behavior: `[-0, +0, v]`
pub fn argError(lua: *Lua, narg: i32, extramsg: []const u8) noreturn;

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
pub const Buffer = opaque {};

/// Initializes a Lua buffer. This function does not allocate any space;
/// the buffer must be declared as a variable.
///
/// From: `void luaL_buffinit(lua_State *L, luaL_Buffer *B);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_buffinit
/// Stack Behavior: `[-0, +0, -]`
pub fn bufInit(lua: *Lua, buffer: *Buffer) void;

/// Calls a metamethod. If the object at the given index has a metatable and this metatable has a
/// field `e`, this function calls this field and passes the object as its only argument. If the
/// metamethod exists, it returns true and pushes the returned value onto the stack. If no
/// metatable or metamethod exists, it returns false without pushing any value.
///
/// From: `int luaL_callmeta(lua_State *L, int obj, const char *e);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_callmeta
/// Stack Behavior: `[-0, +(0|1), e]`
pub fn callMeta(lua: *Lua, obj: i32, e: [*:0]const u8) bool;

/// Loads and runs the given file. It is equivalent to calling `luaL_loadfile(L, filename)` and then `lua_pcall(L, 0, LUA_MULTRET, 0)`.
/// Returns 0 if there are no errors or 1 in case of errors.
///
/// From: `int luaL_dofile(lua_State *L, const char *filename);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_dofile
/// Stack Behavior: `[-0, +?, m]`
pub fn doFile(lua: *Lua, filename: [*:0]const u8) LuaError!void;



/// Pushes onto the stack the field `e` from the metatable of the object at index `obj`.
/// If the object does not have a metatable, or if the metatable does not have this field,
/// returns 0 and pushes nothing.
///
/// From: `int luaL_getmetafield(lua_State *L, int obj, const char *e);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_getmetafield
/// Stack Behavior: `[-0, +(0|1), m]`
pub fn getMetaField(lua: *Lua, obj: i32, e: [:0]const u8) i32;

/// Pushes onto the stack the metatable associated with name tname in the registry.
///
/// From: `void luaL_getmetatable(lua_State *L, const char *tname);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_getmetatable
/// Stack Behavior: `[-0, +1, -]`
pub fn getMetatable(lua: *Lua, name: [*:0]const u8) void;

/// Creates a copy of string s by replacing any occurrence of the string p with the string r.
/// Pushes the resulting string on the stack and returns it.
///
/// From: `const char *luaL_gsub(lua_State *L, const char *s, const char *p, const char *r);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_gsub
/// Stack Behavior: `[-0, +1, m]`
pub fn gSub(lua: *Lua, s: []const u8, p: []const u8, r: []const u8) []const u8;

/// Loads a buffer as a Lua chunk using lua_load to load the chunk in the buffer pointed to by buff with size sz.
/// Returns the same results as lua_load. The name parameter is used for debug information and error messages.
///
/// From: `int luaL_loadbuffer(lua_State *L, const char *buff, size_t sz, const char *name);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_loadbuffer
/// Stack Behavior: `[-0, +1, m]`
pub fn loadBuffer(lua: *Lua, buff: [*]const u8, sz: usize, name: [*:0]const u8) LuaError;

/// Loads a file as a Lua chunk. Uses lua_load to load the chunk in the file named filename.
/// If filename is null, then it loads from the standard input. The first line in the file is ignored
/// if it starts with a #. Returns the same results as lua_load, but with an extra error code LUA_ERRFILE
/// if it cannot open/read the file. Only loads the chunk; it does not run it.
///
/// From: `int luaL_loadfile(lua_State *L, const char *filename);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_loadfile
/// Stack Behavior: `[-0, +1, m]`
pub fn loadFile(lua: *Lua, filename: ?[:0]const u8) LuaError;

/// Loads a string as a Lua chunk using lua_load for the zero-terminated string.
/// This function only loads the chunk and does not run it, returning the same results as lua_load.
///
/// From: `int luaL_loadstring(lua_State *L, const char *s);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_loadstring
/// Stack Behavior: `[-0, +1, m]`
pub fn loadString(lua: *Lua, source: [*:0]const u8) LuaError;

/// If the registry already has the key tname, returns 0. Otherwise, creates a new table to be used as a
/// metatable for userdata, adds it to the registry with key tname, and returns 1. In both cases pushes
/// onto the stack the final value associated with tname in the registry.
///
/// From: `int luaL_newmetatable(lua_State *L, const char *tname);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_newmetatable
/// Stack Behavior: `[-0, +1, m]`
pub fn newMetatable(lua: *Lua, tname: [*:0]const u8) i32;

/// Creates a new Lua state using the standard C realloc function for memory allocation and sets a default
/// panic function that prints an error message to the standard error output in case of fatal errors.
///
/// From: `lua_State *luaL_newstate(void);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_newstate
/// Stack Behavior: `[-0, +0, -]`
pub fn newState() ?*Lua;

/// Returns an address to a space of size LUAL_BUFFERSIZE where you can copy a string to be added to buffer B.
/// After copying the string into this space you must call luaL_addsize with the size of the string to actually
/// add it to the buffer.
///
/// From: `char *luaL_prepbuffer(luaL_Buffer *B);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_prepbuffer
/// Stack Behavior: `[-0, +0, -]`
pub fn prepBuffer(buffer: *Buffer) [*]u8;

/// Finishes the use of buffer B leaving the final string on the top of the stack.
///
/// From: `void luaL_pushresult(luaL_Buffer *B);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_pushresult
/// Stack Behavior: `[-?, +1, m]`
pub fn pushResult(buffer: *LuaBuffer) void;

/// Opens a library. When called with libname equal to null, it simply registers all functions in the list l
/// into the table on the top of the stack. When called with a non-null libname, creates a new table t,
/// sets it as the value of the global variable libname, sets it as the value of package.loaded[libname],
/// and registers on it all functions in the list l. If there is a table in package.loaded[libname] or in
/// variable libname, reuses this table instead of creating a new one. In any case the function leaves
/// the table on the top of the stack.
///
/// From: `void luaL_register(lua_State *L, const char *libname, const luaL_Reg *l);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_register
/// Stack Behavior: `[-(0|1), +1, m]`
pub fn register(lua: *Lua, lib_name: ?[:0]const u8, funcs: []const LuaReg) void;

/// Type for arrays of functions to be registered by `luaL_register`. 
/// `name` is the function name and `func` is a pointer to the function.
/// Any array of `luaL_Reg` must end with a sentinel entry in which both 
/// `name` and `func` are `null`.
///
/// From: `typedef struct luaL_Reg { const char *name; lua_CFunction func; } luaL_Reg;`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_Reg
pub const Reg = extern struct {
    name: ?[*:0]const u8,
    func: ?*const fn (state: *Lua) callconv(.C) c_int,
};

/// Generates an error with a message like "location: bad argument narg to 'func' (tname expected, got rt)",
/// where location is produced by luaL_where, func is the name of the current function,
/// and rt is the type name of the actual argument.
///
/// From: `int luaL_typerror(lua_State *L, int narg, const char *tname);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_typerror
/// Stack Behavior: `[-0, +0, v]`
pub fn typeError(lua: *Lua, narg: i32, tname: [*:0]const u8) i32;

/// Pushes onto the stack a string identifying the current position of the control at level `lvl` in the call stack.
/// Typically this string has the format: `chunkname:currentline:`. 
/// Level 0 is the running function, level 1 is the function that called the running function, etc. 
/// This function is used to build a prefix for error messages.
///
/// From: `void luaL_where(lua_State *L, int lvl);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_where
/// Stack Behavior: `[-0, +1, m]`
pub fn where(lua: *Lua, lvl: i32) void;
