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

    lua.pushCFunction(operator);
    lua.setGlobal("operator");

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
}

/// Any function that can be called from Lua must be of type Lua.CFunction
/// *const fn (lua: *Lua) callconv(.c) i32
fn operator(lua: *Lua) callconv(.c) i32 {
    print("[Zig] Running `operator` function\n", .{});

    // checkNumber is a convenience function that returns the argument at the
    // given index (in the stack) if it is a number, and throws an error otherwise
    const x = lua.checkNumber(-2);
    const y = lua.checkNumber(-1);

    print("[Zig] Got two arguments: {d}, {d}\n", .{ x, y });
    print("[Zig] Multiplying numbers\n", .{});

    lua.pushNumber(x * y);
    return 1; // Return the number of return values provided
}
