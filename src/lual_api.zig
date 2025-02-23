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
