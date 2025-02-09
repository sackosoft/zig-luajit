//! Copyright (c) 2024-2025 Theodore Sackos
//! SPDX-License-Identifier: AGPL-3.0-or-later

const std = @import("std");
const Lua = @import("luajit").Lua;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    const lua = try Lua.init(allocator);
    defer lua.deinit();

    lua.openBaseLib();

    const stdin = std.io.getStdIn();
    const stdout = std.io.getStdOut();

    var buf: [1024]u8 = undefined;

    while (true) {
        try stdout.writeAll("> ");

        const input = try stdin.reader().readUntilDelimiter(&buf, '\n');
        if (input.len == 0) continue;

        if (std.mem.eql(u8, input, "exit")) break;

        lua.doString(input) catch |err| {
            std.debug.print("Error: {}\n", .{err});
            continue;
        };
    }
}
