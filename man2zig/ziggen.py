import textwrap

TYPES = [
    # Hidden as internal to the library. Clients should use `std.mem.Allocator` instances to control this behavior.
    # 'lua_Alloc',
    'lua_CFunction',
    'lua_Debug',
    'lua_Hook',
    'lua_Integer',
    'lua_Number',
    'lua_Reader',
    'lua_State',
    'lua_Writer',
]

C_API = [
    "lua_atpanic",
    "lua_call",
    "lua_checkstack",
    "lua_close",
    "lua_concat",
    "lua_cpcall",
    "lua_createtable",
    "lua_dump",
    "lua_equal",
    "lua_error",
    "lua_gc",
    "lua_getallocf",
    "lua_getfenv",
    "lua_getfield",
    "lua_getglobal",
    "lua_gethook",
    "lua_gethookcount",
    "lua_gethookmask",
    "lua_getinfo",
    "lua_getlocal",
    "lua_getmetatable",
    "lua_getstack",
    "lua_gettable",
    "lua_gettop",
    "lua_getupvalue",
    "lua_insert",
    "lua_isboolean",
    "lua_iscfunction",
    "lua_isfunction",
    "lua_islightuserdata",
    "lua_isnil",
    "lua_isnone",
    "lua_isnoneornil",
    "lua_isnumber",
    "lua_isstring",
    "lua_istable",
    "lua_isthread",
    "lua_isuserdata",
    "lua_lessthan",
    "lua_load",
    "lua_newstate",
    "lua_newtable",
    "lua_newthread",
    "lua_newuserdata",
    "lua_next",
    "lua_objlen",
    "lua_pcall",
    "lua_pop",
    "lua_pushboolean",
    "lua_pushcclosure",
    "lua_pushcfunction",
    "lua_pushfstring",
    "lua_pushinteger",
    "lua_pushlightuserdata",
    "lua_pushliteral",
    "lua_pushlstring",
    "lua_pushnil",
    "lua_pushnumber",
    "lua_pushstring",
    "lua_pushthread",
    "lua_pushvalue",
    "lua_pushvfstring",
    "lua_rawequal",
    "lua_rawget",
    "lua_rawgeti",
    "lua_rawset",
    "lua_rawseti",
    "lua_register",
    "lua_remove",
    "lua_replace",
    "lua_resume",
    "lua_setallocf",
    "lua_setfenv",
    "lua_setfield",
    "lua_setglobal",
    "lua_sethook",
    "lua_setlocal",
    "lua_setmetatable",
    "lua_settable",
    "lua_settop",
    "lua_setupvalue",
    "lua_status",
    "lua_toboolean",
    "lua_tocfunction",
    "lua_tointeger",
    "lua_tolstring",
    "lua_tonumber",
    "lua_topointer",
    "lua_tostring",
    "lua_tothread",
    "lua_touserdata",
    "lua_type",
    "lua_typename",
    "lua_upvalueindex",
    "lua_xmove",
    "lua_yield",
]

AUX_TYPES = [
    'luaL_Buffer',
    'luaL_Reg'
]

AUX_API = [
    "luaL_addchar",
    "luaL_addlstring",
    "luaL_addsize",
    "luaL_addstring",
    "luaL_addvalue",
    "luaL_argcheck",
    "luaL_argerror",
    "luaL_buffinit",
    "luaL_callmeta",
    "luaL_checkany",
    "luaL_checkint",
    "luaL_checkinteger",
    "luaL_checklong",
    "luaL_checklstring",
    "luaL_checknumber",
    "luaL_checkoption",
    "luaL_checkstack",
    "luaL_checkstring",
    "luaL_checktype",
    "luaL_checkudata",
    "luaL_dofile",
    "luaL_dostring",
    "luaL_error",
    "luaL_getmetafield",
    "luaL_getmetatable",
    "luaL_gsub",
    "luaL_loadbuffer",
    "luaL_loadfile",
    "luaL_loadstring",
    "luaL_newmetatable",
    "luaL_newstate",
    "luaL_openlibs",
    "luaL_optint",
    "luaL_optinteger",
    "luaL_optlong",
    "luaL_optlstring",
    "luaL_optnumber",
    "luaL_optstring",
    "luaL_prepbuffer",
    "luaL_pushresult",
    "luaL_ref",
    "luaL_register",
    "luaL_typename",
    "luaL_typerror",
    "luaL_unref",
    "luaL_where",
]

CONSTANTS = [
    'LUA_ENVIRONINDEX',
    'LUA_ERRERR',
    'LUA_ERRFILE',
    'LUA_ERRMEM',
    'LUA_ERRRUN',
    'LUA_ERRSYNTAX',
    'LUA_GLOBALSINDEX',
    'LUA_HOOKCOUNT',
    'LUA_HOOKLINE',
    'LUA_HOOKRET',
    'LUA_MASKCALL',
    'LUA_MASKCOUNT',
    'LUA_MASKLINE',
    'LUA_MASKRET',
    'LUA_MINSTACK',
    'LUA_MULTRET',
    'LUA_NOREF',
    'LUA_REFNIL',
    'LUA_REGISTRYINDEX',
    'LUA_YIELD',
]

def fragment_link(fragment: str) -> str:
    return f"https://www.lua.org/manual/5.1/manual.html#{fragment}"

SPECIAL_TRANSLATIONS = {
    "lua_CFunction": (
            """
                /// Type for C functions.
                ///
                /// In order to communicate properly with Lua, a C function must use the following protocol, which defines the way
                /// parameters and results are passed: a C function receives its arguments from Lua in its stack in direct order (the
                /// first argument is pushed first). So, when the function starts, lua_gettop(L) returns the number of arguments received
                /// by the function. The first argument (if any) is at index 1 and its last argument is at index lua_gettop(L). To
                /// return values to Lua, a C function just pushes them onto the stack, in direct order (the first result is pushed
                /// first), and returns the number of results. Any other value in the stack below the results will be properly discarded
                /// by Lua. Like a Lua function, a C function called by Lua can also return many results.
            """,
            """pub const CFunction = *const fn(state: ?*LuaState) callconv(.C) c_int;"""
        )
}

# Currently the separator between data elements in the same section,
# e.g. between documentation for function definitions.
SEPARATOR = 'hr'

def generate_zig_type(manual, t):
    assert t and len(t), str(t)
    refer_to = fragment_link(t);

    a = manual.find('a', attrs={"name": t})
    assert a is not None, str(a)
    heading = a.parent
    assert heading.name.startswith('h') and len(heading.name) > 1, str(a.parent)

    # Encountered if SEPARATOR is missing and we run into the next data element in the same section
    hx = heading.name

    # Encountered if SEPARATOR is missing and we run into the next section
    # (e.g. after the last function definition, an h3, there is no separator and instead we run into the Debug section, an h2)
    hy = 'h' + str(int(hx.replace('h', '')) - 1)

    item = None
    content = []
    stoppers = { hx, hy, SEPARATOR }

    iter = heading.next_sibling
    while iter and iter.name not in stoppers:
        if item == None and iter.name == 'pre':
            item = iter
        else:
            content.append(str(iter))

        iter = iter.next_sibling

    print('\n'.join(content))
    print(item.text)


def generate_zig_artifacts(manual):
    for t in TYPES:
        generate_zig_type(manual, t);
        break
