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

    print("[Zig] Hello, World!\n", .{});

    // Run some Lua code contained in a string
    lua.doString(
        \\ print("[Lua] Hello, Lua!")
    ) catch unreachable; // We don't care about error handling right now

    // You can also run Lua code in a file
    lua.doFile("./src/script.lua") catch |err| switch (err) {
        error.FileOpenOrFileRead => print("[Zig] Can't find the file 'src/script.lua'. Are you in the correct directory?\n", .{}),
        error.Runtime => {
            // A "Runtime" error is an error that happened while the Lua code was running.
            // In this case, an error message will often be left at the top of the stack.

            const message = lua.toString(-1) catch "unknown"; // If the error message can't be converted to a string, then just use the string "unknown"
            print("[Zig] An error occurred while running the script: {s}\n", .{message});
        },
        else => unreachable,
    };
}
