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

    var buf: [1025]u8 = undefined;
    const read_slice = buf[0..1024];

    while (true) {
        try stdout.writeAll("> ");

        const input = try stdin.reader().readUntilDelimiter(read_slice, '\n');
        if (input.len == 0) continue;

        if (std.mem.eql(u8, input, "exit")) break;

        buf[input.len] = 0;
        const actual = buf[0..input.len :0];

        lua.doString(actual) catch |err| {
            std.debug.print("Error: {}\n", .{err});
            continue;
        };
    }
}
