//! Copyright (c) 2024-2025 Theodore Sackos
//! SPDX-License-Identifier: MIT

const std = @import("std");
const Lua = @import("luajit").Lua;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    const lua = try Lua.init(allocator);
    defer lua.deinit();

    lua.openBaseLib();

    var stdin_buffer: [1024]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().reader(&stdin_buffer);
    const stdin = &stdin_reader.interface;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    var line_buffer: [1025]u8 = undefined;

    while (true) {
        try stdout.writeAll("> ");
        try stdout.flush();

        var line_writer = std.Io.Writer.fixed(&line_buffer);
        const input_len = try stdin.streamDelimiterLimit(&line_writer, '\n', std.Io.Limit.limited(1024));
        if (input_len == 0) continue;

        // Throw away the `\n` on the input.
        stdin.toss(1);

        // Replace the `\n` terminated string with a null terminated (`\0`) string.
        line_buffer[input_len] = '\u{0}';
        const input = line_buffer[0..input_len :0];

        if (std.mem.eql(u8, input[0..4], "exit")) break;
        if (std.mem.eql(u8, input[0..4], "quit")) break;

        lua.doString(input) catch |err| {
            std.debug.print("Error: {}\n", .{err});
            continue;
        };
    }
}
