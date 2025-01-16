const c = @import("c");

pub const LuaType = enum(i5) {
    None = c.LUA_TNONE,
    Nil = c.LUA_TNIL,
    Boolean = c.LUA_TBOOLEAN,
    Light_userdata = c.LUA_TLIGHTUSERDATA,
    Number = c.LUA_TNUMBER,
    String = c.LUA_TSTRING,
    Table = c.LUA_TTABLE,
    Function = c.LUA_TFUNCTION,
    Userdata = c.LUA_TUSERDATA,
    Thread = c.LUA_TTHREAD,
};
