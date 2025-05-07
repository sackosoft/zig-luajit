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

    // Push a number to the top of the stack
    const foo = 123;
    lua.pushNumber(foo);
    // Pop the value at the top of the stack, and set it as the value of the global "foo"
    lua.setGlobal("foo");

    print("[Zig] Set foo to: {d}\n", .{foo});

    lua.doFile("src/script.lua") catch |err| switch (err) {
        error.Runtime => print("[Zig] Runtime error: {s}\n", .{lua.toString(-1) catch "unknown"}),
        else => print("[Zig] Unknown error: {!}\n", .{err}),
    };

    // getGlobal gets the value of the named global and puts it on the top of the stack, and then returns the type of the global
    switch (lua.getGlobal("bar")) {
        .number => {
            const bar = lua.toNumber(-1);
            print("[Zig] Got value of bar in Zig: {d}\n", .{bar});
        },
        else => print("[Zig] bar is not a number for some reason...\n", .{}),
    }
}
