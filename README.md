<div align="center">

# zig-luajit

**Zig ⚡ language bindings for the [LuaJIT](https://luajit.org/) C API. Use `zig-luajit` to run [Lua scripts](https://www.lua.org/) within a Zig application.**

![Ubuntu Regression Tests Badge](https://img.shields.io/github/actions/workflow/status/sackosoft/zig-luajit/tests-ubuntu.yml?label=Tests%20Ubuntu)
![Windows Regression Tests Badge](https://img.shields.io/github/actions/workflow/status/sackosoft/zig-luajit/tests-windows.yml?label=Tests%20Windows)
<!--
![GitHub License](https://img.shields.io/github/license/sackosoft/zig-luajit)
-->

<!--
TODO: Capture attention with a visualization, diagram, demo or other visual placeholder here.
![Placeholder]()
-->

</div>

## About

The goal of the `zig-luajit` project is to provide the most idiomatic Zig language bindings for the LuaJIT C API and C
API Auxilary Library. Additionally the `zig-luajit` project emphasizes safety by making liberal use of runtime safety
checks in `Debug` and `ReleaseSafe` builds and provides full test coverage of the API.

## Zig Version

The `main` branch targets the latest stable Zig version. Currently `0.16.0`.

For other Zig versions look for branches with the named version.

## Installation & Usage

It is recommended that you install `zig-luajit` using `zig fetch`. This will add a `luajit` dependency to your `build.zig.zon` file.

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

```zig
const std = @import("std");
const Lua = @import("luajit").Lua;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const lua = try Lua.init(gpa.allocator());
    defer lua.deinit();

    lua.openBaseLib();

    try lua.doString(
        \\ message = "Hello, world!"
        \\ print(message)
    );
}
```


## Language Binding Coverage Progress

| API                         | Support                               |
|-----------------------------|---------------------------------------|
| Lua C API (`lua_*`)         | 🎉 100% coverage<sup>†</sup> (92/92)  |
| Auxilary Library (`luaL_*`) | 🤩 100% coverage (48/48)              |
| Debug API (`lua_Debug`)     | 🥳 100% coverage (12/12)              |
| LuaJIT Extensions           | *No plans to implement.*              |

*†: Coroutine yield/resume is not yet part of the public `zig-luajit` Zig API, see [#6][ISSUE-6].*

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

| C Type Definition          | Available in `zig-luajit`                                           |
|----------------------------|---------------------------------------------------------------------|
| `lua_State`                | ☑️ `Lua`                                                             |
| `lua_Alloc`                | ➖ Hidden, please use `lua.setAllocator()` and `lua.getAllocator()` |
| `lua_CFunction`            | ☑️ `lua.CFunction`                                                   |
| `lua_Integer`              | ☑️ `Lua.Integer`                                                     |
| `lua_Number`               | ☑️ `Lua.Number`                                                      |
| `lua_Reader`               | ☑️ [`std.io.AnyReader`][ZIG-DOC-ANYREADER]                           |
| `lua_Writer`               | ☑️ [`std.io.AnyWriter`][ZIG-DOC-ANYWRITER]                           |

[ZIG-DOC-ANYREADER]: https://ziglang.org/documentation/master/std/#std.io.AnyReader
[ZIG-DOC-ANYWRITER]: https://ziglang.org/documentation/master/std/#std.io.AnyWriter

| C API Symbols              | Available in `zig-luajit`           |
|----------------------------|-------------------------------------|
| `lua_atpanic`              | ☑️ `lua.atPanic()`                   |
| `lua_call`                 | ☑️ `lua.call()`                      |
| `lua_pcall`                | ☑️📢 `lua.callProtected()`           |
| `lua_cpcall`               | ☑️📢 `lua.callProtectedC()`          |
| `lua_checkstack`           | ☑️ `lua.checkStack()`                |
| `lua_close`                | ☑️📢 `lua.deinit()`                  |
| `lua_concat`               | ☑️ `lua.concat()`                    |
| `lua_createtable`          | ☑️ `lua.createTable()`               |
| `lua_dump`                 | ☑️ `lua.dump()`                      |
| `lua_equal`                | ☑️ `lua.equal()`                     |
| `lua_error`                | ☑️📢 `lua.raiseError()`              |
| `lua_gc`                   | ☑️ `lua.gc()` + `lua.gcIsRunning()`  |
| `lua_getallocf`            | ☑️📢 `lua.getAllocator()`            |
| `lua_getfenv`              | ☑️📢 `lua.getEnvironment()`          |
| `lua_getfield`             | ☑️ `lua.getField()`                  |
| `lua_getglobal`            | ☑️ `lua.getGlobal()`                 |
| `lua_getmetatable`         | ☑️ `lua.getMetatable()`              |
| `lua_gettable`             | ☑️ `lua.getTable()`                  |
| `lua_gettop`               | ☑️ `lua.getTop()`                    |
| `lua_insert`               | ☑️ `lua.insert()`                    |
| `lua_isboolean`            | ☑️ `lua.isBoolean()`                 |
| `lua_iscfunction`          | ☑️ `lua.isCFunction()`               |
| `lua_isfunction`           | ☑️ `lua.isFunction()`                |
| `lua_islightuserdata`      | ☑️ `lua.isLightUserdata()`           |
| `lua_isnil`                | ☑️ `lua.isNil()`                     |
| `lua_isnone`               | ☑️ `lua.isNone()`                    |
| `lua_isnoneornil`          | ☑️ `lua.isNilOrNone()`               |
| `lua_isnumber`             | ☑️ `lua.isNumber()`                  |
| `lua_isstring`             | ☑️ `lua.isString()`                  |
| `lua_istable`              | ☑️ `lua.isTable()`                   |
| `lua_isthread`             | ☑️ `lua.isThread()`                  |
| `lua_isuserdata`           | ☑️ `lua.isUserdata()`                |
| `lua_lessthan`             | ☑️ `lua.lessThan()`                  |
| `lua_load`                 | ☑️ `lua.load()`                      |
| `lua_newstate`             | ☑️📢 `Lua.init()`                    |
| `lua_newtable`             | ☑️ `lua.newTable()`                  |
| `lua_newthread`            | ☑️ `lua.newThread()`                 |
| `lua_newuserdata`          | ☑️ `lua.newUserdata()`               |
| `lua_next`                 | ☑️ `lua.next()`                      |
| `lua_objlen`               | ☑️📢 `lua.getLength()`               |
| `lua_pop`                  | ☑️ `lua.pop()`                       |
| `lua_pushboolean`          | ☑️ `lua.pushBoolean()`               |
| `lua_pushcclosure`         | ☑️ `lua.pushCClosure()`              |
| `lua_pushcfunction`        | ☑️ `lua.pushCFunction()`             |
| `lua_pushfstring`          | ☑️ `lua.pushFString()`               |
| `lua_pushinteger`          | ☑️ `lua.pushInteger()`               |
| `lua_pushlightuserdata`    | ☑️ `lua.pushLightUserdata()`         |
| `lua_pushliteral`          | 🆖 please use `lua.pushLString()`   |
| `lua_pushlstring`          | ☑️ `lua.pushLString()`               |
| `lua_pushnil`              | ☑️ `lua.pushNil()`                   |
| `lua_pushnumber`           | ☑️ `lua.pushNumber()`                |
| `lua_pushstring`           | ☑️ `lua.pushString()`                |
| `lua_pushthread`           | ☑️ `lua.pushThread()`                |
| `lua_pushvalue`            | ☑️ `lua.pushValue()`                 |
| `lua_pushvfstring`         | 🆖 please use `lua.pushFString()`   |
| `lua_rawequal`             | ☑️📢 `lua.equalRaw()`                |
| `lua_rawgeti`              | ☑️📢 `lua.getTableIndexRaw()`        |
| `lua_rawget`               | ☑️📢 `lua.getTableRaw()`             |
| `lua_rawseti`              | ☑️📢 `lua.setTableIndexRaw()`        |
| `lua_rawset`               | ☑️📢 `lua.setTableRaw()`             |
| `lua_register`             | ☑️📢 `lua.registerFunction()`        |
| `lua_remove`               | ☑️ `lua.remove()`                    |
| `lua_replace`              | ☑️ `lua.replace()`                   |
| `lua_resume`               | ➖ Hidden, see [Issue #6][ISSUE-6]  |
| `lua_setallocf`            | ☑️📢 `lua.setAllocator()`            |
| `lua_setfenv`              | ☑️📢 `lua.setEnvironment()`          |
| `lua_setfield`             | ☑️ `lua.setField()`                  |
| `lua_setglobal`            | ☑️ `lua.setGlobal()`                 |
| `lua_setmetatable`         | ☑️ `lua.setMetatable()`              |
| `lua_settable`             | ☑️ `lua.setTable()`                  |
| `lua_settop`               | ☑️ `lua.setTop()`                    |
| `lua_status`               | ☑️ `lua.status()`                    |
| `lua_toboolean`            | ☑️ `lua.toBoolean()`                 |
| `lua_tocfunction`          | ☑️ `lua.toCFunction()`               |
| `lua_tointeger`            | ☑️ `lua.toInteger()`                 |
| `lua_tolstring`            | ☑️ `lua.toLString()`                 |
| `lua_tonumber`             | ☑️ `lua.toNumber()`                  |
| `lua_topointer`            | ☑️ `lua.toPointer()`                 |
| `lua_tostring`             | ☑️ `lua.toString()`                  |
| `lua_tothread`             | ☑️ `lua.toThread()`                  |
| `lua_touserdata`           | ☑️ `lua.toUserdata()`                |
| `lua_type`                 | ☑️📢 `lua.getType()`                 |
| `lua_typename`             | ☑️ `lua.getTypeName()`               |
| `lua_xmove`                | ☑️ `lua.xmove()`                     |
| `lua_yield`                | ➖ Hidden, see [Issue #6][ISSUE-6]  |

[ISSUE-6]: https://github.com/sackosoft/zig-luajit/issues/6


### Auxilary Library Coverage (`luaL_`)

| C Type Definition          | Available in `zig-luajit`           |
|----------------------------|-------------------------------------|
| `luaL_Buffer`              | ☑️ `Lua.Buffer`                      |
| `luaL_Reg`                 | ☑️ `Lua.Reg` and `Lua.RegEnd`        |

| C API Symbol               | Available in `zig-luajit`           |
|----------------------------|-------------------------------------|
| `luaL_addchar`             | ☑️ `buffer.addChar()`|
| `luaL_addsize`             | ☑️ `buffer.addSize()`|
| `luaL_addlstring`          | ☑️ `buffer.addLString()`|
| `luaL_addstring`           | ☑️ `buffer.addString()`|
| `luaL_addvalue`            | ☑️ `buffer.addValue()`|
| `luaL_argcheck`            | ☑️📢 `lua.checkArgument()` |
| `luaL_argerror`            | ☑️📢 `lua.raiseErrorArgument()` |
| `luaL_buffinit`            | ☑️📢 `lua.initBuffer()`|
| `luaL_callmeta`            | ☑️ `lua.callMeta()`|
| `luaL_checkany`            | ☑️ `lua.checkAny()`|
| `luaL_checkinteger`        | ☑️ `lua.checkInteger()` |
| `luaL_checkint`            | 🆖 please use `lua.checkInteger()` |
| `luaL_checklong`           | 🆖 please use `lua.checkInteger()` |
| `luaL_checklstring`        | ☑️ `lua.checkLString()` |
| `luaL_checknumber`         | ☑️ `lua.checkNumber()` |
| `luaL_checkoption`         | ☑️ `lua.checkOption()` |
| `luaL_checkstack`          | ☑️📢 `lua.checkStackOrError()` |
| `luaL_checkstring`         | ☑️ `lua.checkString()` |
| `luaL_checktype`           | ☑️ `lua.checkType()` |
| `luaL_checkudata`          | ☑️ `lua.checkUserdata()`|
| `luaL_dofile`              | ☑️ `lua.doFile()` |
| `luaL_dostring`            | ☑️ `lua.doString()` |
| `luaL_error`               | ☑️📢 `lua.raiseErrorFormat()` |
| `luaL_getmetafield`        | ☑️ `lua.getMetaField()` |
| `luaL_getmetatable`        | ☑️📢 `lua.getMetatableRegistry()` |
| `luaL_gsub`                | ☑️ `lua.gsub()` |
| `luaL_loadbuffer`          | ☑️ `lua.loadBuffer()` |
| `luaL_loadfile`            | ☑️ `lua.loadFile()` |
| `luaL_loadstring`          | ☑️ `lua.loadString()` |
| `luaL_newmetatable`        | ☑️ `lua.newMetatable()` |
| `luaL_newstate`            | 🆖 please use `Lua.init()` |
| `luaL_openlibs`            | ☑️ `lua.openLibs()` |
| `luaL_optinteger`          | ☑️📢 `lua.checkIntegerOptional()` |
| `luaL_optint`              | 🆖 please use `lua.checkIntegerOptional()` |
| `luaL_optlong`             | 🆖 please use `lua.checkIntegerOptional()` |
| `luaL_optlstring`          | ☑️📢 `lua.checkLStringOptional()` |
| `luaL_optnumber`           | ☑️📢 `lua.checkNumberOptional()` |
| `luaL_optstring`           | ☑️📢 `lua.checkStringOptional()` |
| `luaL_prepbuffer`          | ☑️ `buffer.prepBuffer()` |
| `luaL_pushresult`          | ☑️ `buffer.pushResult()` |
| `luaL_ref`                 | ☑️ `lua.ref()` |
| `luaL_unref`               | ☑️ `lua.unref()` |
| `luaL_register`            | ☑️📢 `lua.registerLibrary()` |
| `luaL_typename`            | ☑️ `lua.getTypeNameAt()` |
| `luaL_typerror`            | ☑️📢 `lua.raiseErrorType()` |
| `luaL_where`               | ☑️ `lua.where()` |

### Debug API Coverage (`lua_Debug`)

| C Type Definition          | Available in `zig-luajit`           |
|----------------------------|-------------------------------------|
| `lua_Debug`                | ☑️ `Lua.DebugInfo`                   |
| `lua_Hook`                 | ☑️📢 `Lua.HookFunction`              |

| C API Symbol               | Available in `zig-luajit`           |
|----------------------------|-------------------------------------|
| `lua_getinfo`              | ☑️ `lua.getInfo()`                   |
| `lua_getstack`             | ☑️ `lua.getStack()`                  |
| `lua_gethookcount`         | ☑️ `lua.getHookCount()`              |
| `lua_gethookmask`          | ☑️ `lua.getHookMask()`               |
| `lua_gethook`              | ☑️ `lua.getHook()`                   |
| `lua_sethook`              | ☑️ `lua.setHook()`                   |
| `lua_getlocal`             | ☑️ `lua.getLocal()`                  |
| `lua_setlocal`             | ☑️ `lua.setLocal()`                  |
| `lua_getupvalue`           | ☑️ `lua.getUpvalue()`                |
| `lua_setupvalue`           | ☑️ `lua.setUpvalue()`                |


## Additions to the API in `zig-luajit`

The following functions are added in `zig-luajit` and do not necessarily have a corresponding
function or macro in the C API.

| `zig-luajit` Extension Function | Description |
|---------------------------------|-------------|
| `lua.getInfoFunction()`         | A simplified version of `lua.getInfo()` for inspecting functions, that has a more idiomatic Zig result type. |
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

The `zig-luajit` Zig languge bindings are distributed under the terms of the open and permissive MIT License. The terms of this
license can be found in the [LICENSE](./LICENSE) file.

This project depends on source code and other artifacts from third parties. Information about their respective licenses
can be found in the [COPYRIGHT](./COPYRIGHT.md) file.
* [The LuaJIT Project](https://luajit.org/)
* [Lua](https://www.lua.org/)

## Credits

This project was inspired by [natecraddock/ziglua](https://github.com/natecraddock/ziglua) which provides great
functionality if you're looking to use Lua runtimes other than LuaJIT!

