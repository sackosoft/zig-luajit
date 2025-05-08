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

    // Register the function as a global
    lua.pushCFunction(createPoint);
    lua.setGlobal("create_point");

    // NOTE: The Lua code can't really do anything with the userdata, because Lua can't
    // interact with userdata except through Zig (C) functions, and we haven't registered
    // any functions to modify the userdata
    //
    // For details on how to let Lua interact with userdata in C, see here: https://www.lua.org/pil/28.html

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

const Point = struct {
    x: i64,
    y: i64,
};

fn createPoint(lua: *Lua) callconv(.c) i32 {
    // Get the two arguments
    const x = lua.checkInteger(-2);
    const y = lua.checkInteger(-1);

    // Create a new userdata and put it at the top of the stack
    // `newUserdata` returns a pointer to `anyopaque`, so we need to cast it to a pointer to `Point`
    var point: *Point = @ptrCast(@alignCast(lua.newUserdata(@sizeOf(Point))));

    // Modify the point
    point.x = x;
    point.y = y;

    // Return the userdata on the top of the stack
    return 1;
}
