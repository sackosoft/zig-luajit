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

    if (lua.getGlobal("operator") != .function) {
        print("[Zig] Error: Expected `operator` to be a Lua `function`. Instead got `{s}`\n", .{lua.getTypeName(lua.getType(-1))});
        return;
    }
    // The "operator" function is now at the top of the stack

    const x: Lua.Number = 6;
    const y: Lua.Number = 3;
    print("[Zig] Pushing two arguments onto the stack: {d}, {d}\n", .{ x, y });
    lua.pushNumber(x);
    lua.pushNumber(y);

    const argument_count = 2;
    const return_value_count = 1;

    print("[Zig] Calling function\n", .{});
    lua.callProtected(
        argument_count,
        return_value_count,
        0,
    ) catch |err| switch (err) {
        error.Runtime => {
            print("[Zig] Runtime error: {s}\n", .{lua.toString(-1) catch "unknown"});
            return;
        },
        else => {
            print("[Zig] Unknown error: {!}\n", .{err});
            return;
        },
    };

    if (!lua.isNumber(-1)) {
        print("[Zig] Error: Expected return value to be a Lua `number`, got `{s}`\n", .{lua.getTypeName(lua.getType(-1))});
        return;
    }
    const result = lua.toNumber(-1);

    print("[Zig] Got result: {d}\n", .{result});
}
