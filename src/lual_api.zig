//! Copyright (c) 2024-2025 Theodore Sackos
//! SPDX-License-Identifier: AGPL-3.0-or-later

// This file contains brainstorming and draft translations of the C API to Lua.



/// Creates a new Lua state using the standard C realloc function for memory allocation and sets a default
/// panic function that prints an error message to the standard error output in case of fatal errors.
///
/// From: `lua_State *luaL_newstate(void);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#luaL_newstate
/// Stack Behavior: `[-0, +0, -]`
pub fn newState() ?*Lua;

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
