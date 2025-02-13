<div align="center">

# zig-luajit

**Zig ⚡ language bindings for the [LuaJIT](https://luajit.org/) C API. Use `zig-luajit` to run [Lua scripts](https://www.lua.org/) within a Zig application.**

![Ubuntu Regression Tests Badge](https://img.shields.io/github/actions/workflow/status/sackosoft/zig-luajit/tests-ubuntu.yml?label=Tests%20Ubuntu)
![Windows Regression Tests Badge](https://img.shields.io/github/actions/workflow/status/sackosoft/zig-luajit/tests-windows.yml?label=Tests%20Windows)
![GitHub License](https://img.shields.io/github/license/sackosoft/zig-luajit)

<!--
TODO: Capture attention with a visualization, diagram, demo or other visual placeholder here.
![Placeholder]()
-->

</div>

## About

This project attempts to provide the most idiomatic Zig language bindings for the Lua C API and C API Auxilary Library. The `zig-luajit` project emphasizes
safety by making liberal use of runtime safety checks in `Debug` and `ReleaseSafe` builds. Translations of types and functions is a work in progress and done
completely by human hands -- no `translate-c` or LLMs.

## Zig Version

The `main` branch targets recent builds of Zig's `master` branch (last tested with Zig `0.14.0-dev.3197+1d8857bbe`).

## Installation & Usage

It is recommended that you install `zig-luajit` using `zig fetch`. This will add a `ziglua` dependency to your `build.zig.zon` file.

```bash
zig fetch --save=luajit git+https://github.com/sackosoft/zig-luajit
```

Next, in order for your code to import `zig-luajit`, you'll need to update your `build.zig` to do the following:

1. get a reference the `zig-luajit` dependency.
2. get a reference to the `luajit` module, which contains the core Zig language bindings for LuaJIT.
3. add the module as an import to your executable or library.

```zig
// (1) Get a reference to the `zig fetch`'ed dependency
const luajit_dep = b.dependency("luajit", .{
    .target = target,
    .optimize = optimize,
});

// (2) Get a reference to the language bindings module.
const luajit = luajit_dep.module("luajit");

// Set up your library or executable
const lib = // ...
const exe = // ...

// (3) Add the module as an import to your executable or library.
my_exe.root_module.addImport("luajit", luajit);
my_lib.root_module.addImport("luajit", luajit);
```

Now the code in your library or exectable can import and use the LuaJIT Zig API!

```zig
const luajit = @import("luajit");
const Lua = luajit.Lua;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const lua = Lua.init(gpa.allocator());
defer lua.deinit();

lua.openBaseLib();
lua.doString(
    \\ print("Hello, world!")
);
```

## Examples

Some examples are provided in [examples/](./examples/) to aid users in learning to use `zig-luajit`. These
small self-contained applications should always be working, please create an issue if they do not work for
you.


## Language Binding Coverage Progress

| API | Support |
|---|---|
| Lua C API (`lua_*`) | 90% available (84/92) |
| Auxilary Library (`luaL_*`) | 8% available (4/48) |
| LuaJIT Extensions | *No plans to implement.* |

## Coverage and Compatibility

This section describes the current status of Zig language bindings ("the Zig API").

* ☑️ Fully Supported: Test coverage and runtime safety checks enabled in `Debug` or `ReleaseSafe` builds.
* ➖ Internal: Used internally and intentionally hidden from the Zig API.
* 🆖 Superseded: Has no direct Zig equivalent, but the functionality is provided by a different part of the Zig API.
* 📢 Renamed: Renamed in a non-obvious way from the C API. Renaming is avoided but done in cases deemed required:
    1. to conform to Zig idioms or patterns, such as the `init()` / `deinit()` pattern.
    1. to avoid conflicts with Zig language keywords, such as the Zig `error` keyword.
    1. to show that the Zig API has slightly different behavior than the C API, such as using `lua.setAllocator()`
       instead of `lua.setAllocF()`; since the Zig API uses `std.mem.Allocator` instead of allocation functions.
    1. to improve the clarity, discoverability or consistency of the symbol in the overall API surface.


### Core C API Coverage (`lua_`)

| C Type Definition | Available in `zig-luajit` |
|--------------|---------------------------|
| `lua_State`| ☑️ `Lua` |
| `lua_Alloc`| ➖ Hidden, please use `lua.setAllocator()` and `lua.getAllocator()` |
| `lua_CFunction`| ☑️ `lua.CFunction` |
| `lua_Integer`| ☑️ `Lua.Integer` |
| `lua_Number`| ☑️ `Lua.Number` |
| `lua_Reader`||
| `lua_Writer`||

| C API Symbols | Available in `zig-luajit` |
|--------------|---------------------------|
| `lua_atpanic`| ☑️ `lua.atPanic()` |
| `lua_call`| ☑️ `lua.call()` |
| `lua_checkstack`| ☑️ `lua.checkStack()` |
| `lua_close`| ☑️📢 `lua.deinit()` |
| `lua_concat`| ☑️ `lua.concat()` |
| `lua_cpcall`| ☑️📢 `lua.protectedCallCFunction()` |
| `lua_createtable`| ☑️ `lua.createTable()` |
| `lua_dump`||
| `lua_equal`| ☑️ `lua.equal()` |
| `lua_error`| ☑️📢 `lua.raiseError()` |
| `lua_gc`| ☑️ `lua.gc()` + `lua.gcIsRunning()` |
| `lua_getallocf`| ☑️📢 `lua.getAllocator()` |
| `lua_getfenv`| ☑️📢 `lua.getEnvironment()` |
| `lua_getfield`| ☑️ `lua.getField()` |
| `lua_getglobal`| ☑️ `lua.getGlobal()` |
| `lua_getmetatable`| ☑️ `lua.getMetatable()` |
| `lua_gettop`| ☑️ `lua.getTop()` |
| `lua_insert`| ☑️ `lua.insert()` |
| `lua_isboolean`| ☑️ `lua.isBoolean()` |
| `lua_iscfunction`| ☑️ `lua.isCFunction()` |
| `lua_isfunction`| ☑️ `lua.isFunction()` |
| `lua_islightuserdata`| ☑️ `lua.isLightUserdata()` |
| `lua_isnil`| ☑️ `lua.isNil()` |
| `lua_isnoneornil`| ☑️ `lua.isNilOrNone()` |
| `lua_isnone`| ☑️ `lua.isNone()` |
| `lua_isnumber`| ☑️ `lua.isNumber()` |
| `lua_isstring`| ☑️ `lua.isString()` |
| `lua_istable`| ☑️ `lua.isTable()` |
| `lua_isthread`| ☑️ `lua.isThread()` |
| `lua_isuserdata`| ☑️ `lua.isUserdata()` |
| `lua_lessthan`| ☑️ `lua.lessThan()` |
| `lua_load`||
| `lua_newstate`| ☑️📢 `Lua.init()` |
| `lua_newtable`| ☑️ `lua.newTable()` |
| `lua_newthread`| ☑️ `lua.newThread()` |
| `lua_newuserdata`| ☑️ `lua.newUserdata()` |
| `lua_next`| ☑️ `lua.next()` |
| `lua_objlen`| ☑️📢 `lua.lengthOf()` |
| `lua_pcall`| ☑️📢 `lua.protectedCall()` |
| `lua_pop`| ☑️ `lua.pop()` |
| `lua_pushboolean`| ☑️ `lua.pushBoolean()` |
| `lua_pushcclosure`| ☑️ `lua.pushCClosure()` |
| `lua_pushcfunction`| ☑️ `lua.pushCFunction()` |
| `lua_pushfstring`| ☑️ `lua.pushFString()` |
| `lua_pushinteger`| ☑️ `lua.pushInteger()`|
| `lua_pushlightuserdata`| ☑️ `lua.pushLightUserdata()`|
| `lua_pushliteral`| 🆖 please use `lua.pushLString()` |
| `lua_pushlstring`| ☑️ `lua.pushLString()` |
| `lua_pushnil`| ☑️ `lua.pushNil()`|
| `lua_pushnumber`| ☑️ `lua.pushNumber()` |
| `lua_pushstring`| ☑️ `lua.pushString()` |
| `lua_pushthread`| ☑️ `lua.pushString()` |
| `lua_pushvalue`| ☑️ `lua.pushValue()` |
| `lua_pushvfstring`| 🆖 please use `lua.pushFString()` |
| `lua_gettable`| ☑️ `lua.getTable()` |
| `lua_rawequal`| ☑️📢 `lua.equalRaw()` |
| `lua_settable`| ☑️ `lua.setTable()` |
| `lua_rawget`| ☑️📢 `lua.getTableRaw()` |
| `lua_rawset`| ☑️📢 `lua.setTableRaw()` |
| `lua_rawgeti`| ☑️📢 `lua.getTableIndexRaw()` |
| `lua_rawseti`| ☑️📢 `lua.setTableIndexRaw()` |
| `lua_register`| ☑️ `lua.register()` |
| `lua_remove`| ☑️ `lua.remove()` |
| `lua_replace`| ☑️ `lua.replace()` |
| `lua_resume`||
| `lua_setallocf`| ☑️📢 `lua.setAllocator()` |
| `lua_setfenv`| ☑️📢 `lua.setEnvironment()` |
| `lua_setfield`| ☑️ `lua.setField()` |
| `lua_setglobal`| ☑️ `lua.setGlobal()` |
| `lua_setmetatable`| ☑️ `lua.setMetatable()` |
| `lua_settop`| ☑️ `lua.setTop()` |
| `lua_status`| ☑️ `lua.status()` |
| `lua_toboolean`| ☑️ `lua.toBoolean()`|
| `lua_tocfunction`| ☑️ `lua.toCFunction()`|
| `lua_tointeger`| ☑️ `lua.toInteger()`|
| `lua_tolstring`| ☑️ `lua.toLString()`|
| `lua_tonumber`| ☑️ `lua.toNumber()`|
| `lua_topointer`| ☑️ `lua.toPointer()`|
| `lua_tostring`| ☑️ `lua.toString()`|
| `lua_tothread`| ☑️ `lua.toThread()`|
| `lua_touserdata`| ☑️ `lua.toUserdata()`|
| `lua_typename`| ☑️ `lua.typeName()`|
| `lua_type`| ☑️📢 `lua.typeOf()` |
| `lua_xmove`| ☑️ `lua.xmove()`|
| `lua_yield`||

The `zig-luajit` project has not yet reached the 1.0 release, the API is subject to change without notice.


### Auxilary Library Coverage (`luaL_`)

| C API Symbol | Available in `zig-luajit` |
|--------------|---------------------------|
| `luaL_addchar`||
| `luaL_addlstring`||
| `luaL_addsize`||
| `luaL_addstring`||
| `luaL_addvalue`||
| `luaL_argcheck`||
| `luaL_argerror`||
| `luaL_Buffer`||
| `luaL_buffinit`||
| `luaL_callmeta`||
| `luaL_checkany`||
| `luaL_checkinteger`| ☑️ `lua.checkInteger()`|
| `luaL_checkint`||
| `luaL_checklong`||
| `luaL_checklstring`||
| `luaL_checknumber`||
| `luaL_checkoption`||
| `luaL_checkstack`||
| `luaL_checkstring`||
| `luaL_checktype`||
| `luaL_checkudata`||
| `luaL_dofile`||
| `luaL_dostring`| ☑️ `lua.doString()` |
| `luaL_error`||
| `luaL_getmetafield`||
| `luaL_getmetatable`||
| `luaL_gsub`||
| `luaL_loadbuffer`||
| `luaL_loadfile`||
| `luaL_loadstring`||
| `luaL_newmetatable`||
| `luaL_newstate`||
| `luaL_openlibs`| ☑️ `lua.openLibs()` |
| `luaL_optinteger`||
| `luaL_optint`||
| `luaL_optlong`||
| `luaL_optlstring`||
| `luaL_optnumber`||
| `luaL_optstring`||
| `luaL_prepbuffer`||
| `luaL_pushresult`||
| `luaL_ref`||
| `luaL_register`||
| `luaL_Reg`||
| `luaL_typename`| ☑️ `lua.typeName()` |
| `luaL_typerror`||
| `luaL_unref`||
| `luaL_where`||

## Additions to the API in `zig-luajit`

The following functions are added in `zig-luajit` and do not necessarily have a corresponding
function or macro in the C API.

| `zig-luajit` Extension Function | Description |
|---------------------------------|-------------|
| `lua.toNumberStrict()`          | Gets the value of a number on the stack, without doing type coersion (e.g. from string values). |
| `lua.toIntegerStrict()`         | Gets the value of an integer on the stack, without doing type coersion (e.g. from string values). |
| `lua.toBooleanStrict()`         | Gets the value of a boolean on the stack, without doing type coersion based on "truthyness" of the value. |
| `lua.openBaseLib()`             | Opens the `Base` Lua standard library. |
| `lua.openMathLib()`             | Opens the `Math` Lua standard library. |
| `lua.openStringLib()`           | Opens the `String` Lua standard library. |
| `lua.openTableLib()`            | Opens the `Table` Lua standard library. |
| `lua.openIOLib()`               | Opens the `IO` Lua standard library. |
| `lua.openOSLib()`               | Opens the `OS` Lua standard library. |
| `lua.openPackageLib()`          | Opens the `Package` Lua standard library. |
| `lua.openDebugLib()`            | Opens the `Debug` Lua standard library. |
| `lua.openBitLib()`              | Opens the `Bit` LuaJIT standard library. |
| `lua.openJITLib()`              | Opens the `JIT` LuaJIT standard library. |
| `lua.openFFILib()`              | Opens the `FFI` LuaJIT standard library. |
| `lua.openStringBufferLib()`     | Opens the `StringBuffer` LuaJIT standard library. |


## Licensing

The `zig-luajit` Zig languge bindings are distributed under the terms of the AGPL-3.0 License. The terms of this
license can be found in the [LICENSE](./LICENSE) file.

This project depends on source code and other artifacts from third parties. Information about their respective licenses
can be found in the [COPYRIGHT](./COPYRIGHT.md) file.
* [The LuaJIT Project](https://luajit.org/)
* [Lua](https://www.lua.org/)
