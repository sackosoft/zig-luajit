//! Copyright (c) 2024-2025 Theodore Sackos
//! SPDX-License-Identifier: AGPL-3.0-or-later

const std = @import("std");
const print = std.debug.print;
const Lua = @import("luajit").Lua;

pub fn main() !void {
    // Boilerplate
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    const lua = try Lua.init(allocator);
    defer lua.deinit();
    // End boilerplate

    lua.openBaseLib();

    print("[Zig] Running script\n", .{});

    lua.doFile("./src/script.lua") catch |err| switch (err) {
        error.Runtime => {
            print("[Zig] Runtime error: {s}\n", .{lua.toString(-1) catch "unknown"});
            return;
        },
        error.FileOpenOrFileRead => {
            print("[Zig] Can't find the file 'src/script.lua'. Are you in the correct directory?\n", .{});
            return;
        },
        else => {
            print("[Zig] Unknown error: {!}\n", .{err});
            return;
        },
    };

    // Place the table on the top of the stack, and check its type
    if (lua.getGlobal("my_table") != .table) {
        print("[Zig] Error: Expected `my_table` global to be a Lua `table`, got `{s}`\n", .{lua.getTypeNameAt(-1)});
        return;
    }
    // Save the index of the table, because -1 will not work after getting the table's fields
    const my_table_idx = lua.getTop();

    // Put the value of my_table["a"] onto the top of the stack
    //
    // NOTE: If you want to access indices of array-like tables (e.g. `my_array = { "a", "b", "c" }`),
    // use `lua.getTableIndexRaw()`
    if (lua.getField(my_table_idx, "a") != .number) {
        print("[Zig] Error: Expected `my_table['a']` to be a Lua `number`, got `{s}`\n", .{lua.getTypeNameAt(-1)});
        return;
    }
    const my_table_a = lua.toNumber(-1); // We've already checked the type. We know it's a number
    if (lua.getField(my_table_idx, "b") != .string) {
        print("[Zig] Error: Expected `my_table['b']` to be a Lua `string`, got `{s}`\n", .{lua.getTypeNameAt(-1)});
        return;
    }
    const my_table_b = try lua.toString(-1);
    if (lua.getField(my_table_idx, "c") != .boolean) {
        print("[Zig] Error: Expected `my_table['c']` to be a Lua `boolean`, got `{s}`\n", .{lua.getTypeNameAt(-1)});
        return;
    }
    const my_table_c = lua.toBoolean(-1);

    print(
        "[Zig] Got table `my_table` from Lua with:\n  a = {d}\n  b = \"{s}\"\n  c = {}\n",
        .{ my_table_a, my_table_b, my_table_c },
    );
}
