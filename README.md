<div align="center">

# zig-luajit

**Zig ⚡ language bindings for the [LuaJIT](https://luajit.org/) C API. Use `zig-luajit` to run [Lua scripts](https://www.lua.org/) within a Zig application.**

![Regression Tests Badge](https://img.shields.io/github/actions/workflow/status/sackosoft/zig-luajit/tests.yml?label=tests)
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

The `main` branch targets Zig's `master` (nightly) deployment (currently `0.14.0-dev.XXXX`).

## Installation & Usage

It is recommended that you install `zig-luajit` using `zig fetch`. This will add a `ziglua` dependency to your `build.zig.zon` file.

```bash
zig fetch --save=luajit_build git+https://github.com/sackosoft/zig-luajit
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


## Language Binding Coverage Progress

| API | Support |
|---|---|
| Lua C API (`lua_*`) | 46% available (43/92) |
| Auxilary Library (`luaL_*`) | 6% available (3/48) |
| LuaJIT Extensions | *No plans to implement.* |

## C API Coverage (`lua_`)

Icons:

- ☑️ indicates full Zig support with appropriate runtime safety checks in non-release builds.
- 📢 indicates symbols that were renamed in a non-obvious way, such as `lua_objlen` becoming `lua.lengthOf`, or cases where the usage
pattern has changed, such as using the Zig `init()` function pattern instead of using `lua_newstate()` directly.
- ➖ indicates a symbol that is supported internally, but not available in the public API surface.

| C API Symbol | Available in `zig-luajit` |
|--------------|---------------------------|
| `lua_Alloc`||
| `lua_atpanic`||
| `lua_call`|☑️ `lua.call()` |
| `lua_CFunction`|☑️ `lua.CFunction` |
| `lua_checkstack`|☑️ `lua.checkStack()` |
| `lua_close`||
| `lua_concat`||
| `lua_cpcall`||
| `lua_createtable`|☑️ `lua.createTable()` |
| `lua_dump`||
| `lua_equal`||
| `lua_error`||
| `lua_gc`||
| `lua_getallocf`|➖ `lua.getAllocF()` |
| `lua_getfenv`||
| `lua_getfield`||
| `lua_getglobal`||
| `lua_getmetatable`||
| `lua_gettable`|☑️ `lua.getTable()` |
| `lua_gettop`|☑️ `lua.getTop()` |
| `lua_insert`|☑️ `lua.insert()` |
| `lua_Integer`|☑️ `Lua.Integer` |
| `lua_isboolean`|☑️ `lua.isBoolean()` |
| `lua_iscfunction`|☑️ `lua.isCFunction()` |
| `lua_isfunction`|☑️ `lua.isFunction()` |
| `lua_islightuserdata`|☑️ `lua.isLightUserdata()` |
| `lua_isnil`|☑️ `lua.isNil()` |
| `lua_isnoneornil`|☑️ `lua.isNilOrNone()` |
| `lua_isnone`|☑️ `lua.isNone()` |
| `lua_isnumber`|☑️ `lua.isNumber()` |
| `lua_isstring`|☑️ `lua.isString()` |
| `lua_istable`|☑️ `lua.isTable()` |
| `lua_isthread`|☑️ `lua.isThread()` |
| `lua_isuserdata`|☑️ `lua.isUserdata()` |
| `lua_lessthan`||
| `lua_load`||
| `lua_newstate`|☑️📢 `Lua.init()` |
| `lua_newtable`|☑️ `lua.newTable()` |
| `lua_newthread`||
| `lua_newuserdata`||
| `lua_next`|☑️ `lua.next()` |
| `lua_Number`|☑️ `Lua.Number` |
| `lua_objlen`|☑️📢 `lua.lengthOf()` |
| `lua_pcall`|☑️📢 `lua.protectedCall()` |
| `lua_pop`|☑️ `lua.pop()` |
| `lua_pushboolean`|☑️ `lua.pushBoolean()` |
| `lua_pushcclosure`||
| `lua_pushcfunction`||
| `lua_pushfstring`||
| `lua_pushinteger`|☑️ `lua.pushInteger()`|
| `lua_pushlightuserdata`||
| `lua_pushliteral`||
| `lua_pushlstring`|☑️ `lua.pushLString()` |
| `lua_pushnil`|☑️ `lua.pushNil()`|
| `lua_pushnumber`|☑️ `lua.pushNumber()` |
| `lua_pushstring`|☑️ `lua.pushString()` |
| `lua_pushthread`||
| `lua_pushvalue`||
| `lua_pushvfstring`||
| `lua_rawequal`||
| `lua_rawgeti`||
| `lua_rawget`||
| `lua_rawseti`||
| `lua_rawset`||
| `lua_Reader`||
| `lua_register`||
| `lua_remove`||
| `lua_replace`||
| `lua_resume`||
| `lua_setallocf`|➖ `lua.setAllocF()`|
| `lua_setfenv`||
| `lua_setfield`||
| `lua_setglobal`||
| `lua_setmetatable`||
| `lua_settable`|☑️ `lua.setTable()` |
| `lua_settop`||
| `lua_State`|☑️ `Lua` |
| `lua_status`||
| `lua_toboolean`|☑️ `lua.toBoolean()`|
| `lua_tocfunction`||
| `lua_tointeger`|☑️ `lua.toInteger()`|
| `lua_tolstring`|☑️ `lua.toLString()`|
| `lua_tonumber`|☑️ `lua.toNumber()`|
| `lua_topointer`||
| `lua_tostring`|☑️ `lua.toString()`|
| `lua_tothread`||
| `lua_touserdata`||
| `lua_typename`|☑️ `lua.typeName()`|
| `lua_type`|☑️📢 `lua.typeOf()` |
| `lua_Writer`||
| `lua_xmove`||
| `lua_yield`||


## Auxilary Library (`luaL_`)

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
| `luaL_checkinteger`||
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
| `luaL_dostring`|☑️ `doString()` |
| `luaL_error`||
| `luaL_getmetafield`||
| `luaL_getmetatable`||
| `luaL_gsub`||
| `luaL_loadbuffer`||
| `luaL_loadfile`||
| `luaL_loadstring`||
| `luaL_newmetatable`||
| `luaL_newstate`||
| `luaL_openlibs`|☑️ `openLibs()` |
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
| `luaL_typename`|☑️ `typeName()` |
| `luaL_typerror`||
| `luaL_unref`||
| `luaL_where`||

## Additions to the API in `zig-luajit`

| C API Symbol          | Description |
|-----------------------|-------------|
| `toNumberStrict`      | Gets the value of a number on the stack, without doing type coersion (e.g. from string values). |
| `toIntegerStrict`     | Gets the value of an integer on the stack, without doing type coersion (e.g. from string values). |
| `toBooleanStrict`     | Gets the value of a boolean on the stack, without doing type coersion based on "truthyness" of the value. |
| `openBaseLib`         | Opens the `Base` Lua standard library. |
| `openMathLib`         | Opens the `Math` Lua standard library. |
| `openStringLib`       | Opens the `String` Lua standard library. |
| `openTableLib`        | Opens the `Table` Lua standard library. |
| `openIOLib`           | Opens the `IO` Lua standard library. |
| `openOSLib`           | Opens the `OS` Lua standard library. |
| `openPackageLib`      | Opens the `Package` Lua standard library. |
| `openDebugLib`        | Opens the `Debug` Lua standard library. |
| `openBitLib`          | Opens the `Bit` LuaJIT standard library. |
| `openJITLib`          | Opens the `JIT` LuaJIT standard library. |
| `openFFILib`          | Opens the `FFI` LuaJIT standard library. |
| `openStringBufferLib` | Opens the `StringBuffer` LuaJIT standard library. |
