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


/// Pushes onto the stack the environment table of the value at the given index.
///
/// From: `void lua_getfenv(lua_State *L, int index);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_getfenv
/// Stack Behavior: `[-0, +1, -]`
pub fn getfenv(lua: *Lua, index: i32) void;

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

/// Creates a new thread, pushes it on the stack, and returns a pointer to a Lua state that represents this new thread.
/// The new state shares all global objects (such as tables) with the original state, but has an independent execution stack.
/// Threads are subject to garbage collection, like any Lua object.
///
/// From: `lua_State *lua_newthread(lua_State *L);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_newthread
/// Stack Behavior: `[-0, +1, m]`
pub fn newThread(lua: *Lua) *Lua;

/// Allocates a new block of memory with the given size, pushes onto the stack a new full userdata with the block
/// address, and returns this address. Userdata represent C values in Lua. A full userdata represents a block of
/// memory. It is an object (like a table): you must create it, it can have its own metatable, and you can detect
/// when it is being collected. A full userdata is only equal to itself (under raw equality).
///
/// When Lua collects a full userdata with a `gc` metamethod, Lua calls the metamethod and marks the userdata as
/// finalized. When this userdata is collected again then Lua frees its corresponding memory.
///
/// From: `void *lua_newuserdata(lua_State *L, size_t size);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_newuserdata
/// Stack Behavior: `[-0, +1, m]`
pub fn newUserdata(lua: *Lua, size: usize) *anyopaque;



/// The type of numbers in Lua. By default, this is a double-precision floating point number,
/// but can be configured to use other numeric types like float or long through luaconf.h.
///
/// From: `typedef double lua_Number;`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_Number
pub const Number = f64;







/// Pushes a string literal directly onto the stack. This is equivalent to `lua_pushlstring`, but can be used
/// only when the input is a literal string. It automatically provides the string length.
///
/// From: `void lua_pushliteral(lua_State *L, const char *s);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_pushliteral
/// Stack Behavior: `[-0, +1, m]`
pub fn pushLiteral(lua: *Lua, s: []const u8) void;

/// Pushes the thread represented by L onto the stack. Returns 1 if this thread is the main thread of its state.
///
/// From: `int lua_pushthread(lua_State *L);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_pushthread
/// Stack Behavior: `[-0, +1, -]`
pub fn pushThread(lua: *Lua) bool;

/// Equivalent to pushFString, except that it receives a va_list instead of a variable number of arguments.
///
/// From: `const char *lua_pushvfstring(lua_State *L, const char *fmt, va_list argp);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_pushvfstring
/// Stack Behavior: `[-0, +1, m]`
pub fn pushVFString(lua: *Lua, fmt: [*]const u8, argp: std.builtin.VaList) [*]const u8;

/// Similar to `lua_settable`, but does a raw assignment (i.e., without metamethods).
///
/// From: `void lua_rawset(lua_State *L, int index);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_rawset
/// Stack Behavior: `[-2, +0, m]`
pub fn rawSet(lua: *Lua, index: i32) void;

/// A reader function type used by `lua_load` for loading chunks of code. The function is called repeatedly
/// to retrieve pieces of a chunk. It must return a pointer to a memory block with a new piece of the chunk
/// and set the size parameter. To signal the end of the chunk, it must return null or set size to zero.
/// The reader may return pieces of any size greater than zero.
///
/// From: `typedef const char * (*lua_Reader)(lua_State *L, void *data, size_t *size);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_Reader
pub const Reader = *const fn (lua: *Lua, data: *anyopaque, size: *usize) ?[*]const u8;

/// Sets the C function f as the new value of global name.
///
/// From: `void lua_register(lua_State *L, const char *name, lua_CFunction f);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_register
/// Stack Behavior: `[-0, +0, e]`
pub fn register(lua: *Lua, name: [*:0]const u8, func: CFunction) void;

/// Removes the element at the given valid index, shifting down the elements above this index to fill the gap.
/// Cannot be called with a pseudo-index, because a pseudo-index is not an actual stack position.
///
/// From: `void lua_remove(lua_State *L, int index);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_remove
/// Stack Behavior: `[-1, +0, -]`
pub fn remove(lua: *Lua, index: i32) void;

/// Moves the top element into the given position (and pops it), without shifting any element
/// (therefore replacing the value at the given position).
///
/// From: `void lua_replace(lua_State *L, int index);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_replace
/// Stack Behavior: `[-1, +0, -]`
pub fn replace(lua: *Lua, index: i32) void;

/// Starts and resumes a coroutine in a given thread. To start a coroutine, you first create a new thread
/// (see https://www.lua.org/manual/5.1/manual.html#lua_newthread); then you push onto its stack the main function 
/// plus any arguments; then you call lua_resume, with narg being the number of arguments. 
///
/// Returns LUA_YIELD if the coroutine yields, 0 if the coroutine finishes its execution without errors, 
/// or an error code in case of errors. In case of errors, the stack is not unwound, so you can use the debug API over it. 
/// The error message is on the top of the stack.
///
/// Note: This function was renamed from `resume` due to naming conflicts with Zig's `resume` keyword.
///
/// From: `int lua_resume(lua_State *L, int narg);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_resume
/// Stack Behavior: `[-?, +?, -]`
pub fn resumeCoroutine(lua: *Lua, narg: i32) i32;

/// Pops a table from the stack and sets it as the new environment for the value at the given index.
/// Returns true if the value is a function, thread, or userdata, otherwise returns false.
///
/// From: `int lua_setfenv(lua_State *L, int index);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_setfenv
/// Stack Behavior: `[-1, +0, -]`
pub fn setFenv(lua: *Lua, index: i32) bool;

/// Opaque structure that keeps the whole state of a Lua interpreter. The Lua library is fully reentrant:
/// it has no global variables. All information about a state is kept in this structure. A pointer
/// to this state must be passed as the first argument to every function in the library, except 
/// to `lua_newstate`, which creates a Lua state from scratch.
///
/// From: `typedef struct lua_State lua_State;`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_State
pub const Lua = opaque {};


/// Converts a value at the given acceptable index to a C function. 
/// That value must be a C function; otherwise, returns null.
///
/// From: `lua_CFunction lua_tocfunction(lua_State *L, int index);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_tocfunction
/// Stack Behavior: `[-0, +0, -]`
pub fn toCFunction(lua: *Lua, index: i32) ?*const fn(*Lua) i32;


/// Converts the value at the given acceptable index to a generic pointer. The value can be a userdata,
/// a table, a thread, or a function; otherwise, returns null. Different objects will give different pointers.
/// There is no way to convert the pointer back to its original value. Typically this function is used
/// only for debug information.
///
/// From: `const void *lua_topointer(lua_State *L, int index);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_topointer
/// Stack Behavior: `[-0, +0, -]`
pub fn toPointer(lua: *Lua, index: i32) ?*anyopaque;

/// Converts the value at the given acceptable index to a Lua thread. This value must be a thread;
/// otherwise, the function returns null.
///
/// From: `lua_State *lua_tothread(lua_State *L, int index);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_tothread
/// Stack Behavior: `[-0, +0, -]`
pub fn toThread(lua: *Lua, index: i32) ?*Lua;

/// The type of the writer function used by lua_dump. Every time it produces another piece of chunk,
/// lua_dump calls the writer, passing along the buffer to be written (p), its size (sz),
/// and the data parameter supplied to lua_dump. The writer returns an error code:
/// 0 means no errors; any other value means an error and stops lua_dump from calling the writer again.
///
/// From: `typedef int (*lua_Writer)(lua_State *L, const void* p, size_t sz, void* ud);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_Writer
pub const Writer = *const fn (lua: *Lua, buffer: *const anyopaque, size: usize, userdata: *anyopaque) i32;

/// Exchange values between different threads of the same global state. This function pops n values
/// from the stack from, and pushes them onto the stack to.
///
/// From: `void lua_xmove(lua_State *from, lua_State *to, int n);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_xmove
/// Stack Behavior: `[-?, +?, -]`
pub fn xmove(from: *Lua, to: *Lua, n: i32) void;

/// Yields a coroutine. This function should only be called as the return expression of a C function.
/// When a C function calls lua_yield, the running coroutine suspends its execution, and the call 
/// to lua_resume that started this coroutine returns. The parameter nresults is the number of 
/// values from the stack that are passed as results to lua_resume.
///
/// From: `int lua_yield(lua_State *L, int nresults);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_yield
/// Stack Behavior: `[-?, +?, -]`
pub fn yield(lua: *Lua, nresults: i32) i32;