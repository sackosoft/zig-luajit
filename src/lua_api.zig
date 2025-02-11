//! Copyright (c) 2024-2025 Theodore Sackos
//! SPDX-License-Identifier: AGPL-3.0-or-later

// This file contains brainstorming and draft translations of the C API to Lua.


/// Dumps a function as a binary chunk. Receives a Lua function on the top of the stack and produces a
/// binary chunk that, if loaded again, results in a function equivalent to the one dumped. As it produces
/// parts of the chunk, lua_dump calls function writer (see https://www.lua.org/manual/5.1/manual.html#lua_Writer)
/// with the given data to write them. The value returned is the error code returned by the last call to
/// the writer; 0 means no errors. This function does not pop the Lua function from the stack.
///
/// From: `int lua_dump(lua_State *L, lua_Writer writer, void *data);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_dump
/// Stack Behavior: `[-0, +0, m]`
pub fn dump(lua: *Lua, writer: LuaWriter, data: *anyopaque) i32;


/// The type used by the Lua API to represent integral values. 
/// By default it is a signed integral type that the machine handles "comfortably".
///
/// From: `typedef ptrdiff_t lua_Integer;`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_Integer
pub const Integer = isize;

/// Loads a Lua chunk. If there are no errors, pushes the compiled chunk as a Lua function on top of the stack.
/// Otherwise, it pushes an error message. Returns:
/// - 0: no errors
/// - LUA_ERRSYNTAX: syntax error during pre-compilation
/// - LUA_ERRMEM: memory allocation error
///
/// This function only loads a chunk; it does not run it. Automatically detects whether the chunk is text or binary.
///
/// From: `int lua_load(lua_State *L, lua_Reader reader, void *data, const char *chunkname);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_load
/// Stack Behavior: `[-0, +1, -]`
pub fn load(lua: *Lua, reader: lua.Reader, data: ?*anyopaque, chunkname: ?[:0]const u8) lua.Status;



/// The type of the writer function used by lua_dump. Every time it produces another piece of chunk,
/// lua_dump calls the writer, passing along the buffer to be written (p), its size (sz),
/// and the data parameter supplied to lua_dump. The writer returns an error code:
/// 0 means no errors; any other value means an error and stops lua_dump from calling the writer again.
///
/// From: `typedef int (*lua_Writer)(lua_State *L, const void* p, size_t sz, void* ud);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_Writer
pub const Writer = *const fn (lua: *Lua, buffer: *const anyopaque, size: usize, userdata: *anyopaque) i32;

/// A reader function type used by `lua_load` for loading chunks of code. The function is called repeatedly
/// to retrieve pieces of a chunk. It must return a pointer to a memory block with a new piece of the chunk
/// and set the size parameter. To signal the end of the chunk, it must return null or set size to zero.
/// The reader may return pieces of any size greater than zero.
///
/// From: `typedef const char * (*lua_Reader)(lua_State *L, void *data, size_t *size);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_Reader
pub const Reader = *const fn (lua: *Lua, data: *anyopaque, size: *usize) ?[*]const u8;