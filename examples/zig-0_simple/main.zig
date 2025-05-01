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

    // Create a table called "ziglib" and register the function described by `avg_sum_reg` on it.
    lua.registerLibrary(
        "ziglib",
        &.{ avg_sum_reg, Lua.RegEnd },
    );

    try lua.doString(
        \\ print("Hello from Lua!")
        \\ print(ziglib.avgsum(1, 2, 3, 4, 5))
        \\ print("^       ^ These numbers are an average and sum")
    );
}

// `Lua.Reg` is a structure that describes a
// function to be registered to be accessed from Lua
const avg_sum_reg = Lua.Reg{
    .name = "avgsum",
    .func = averageAndSum,
};
/// Calculate the sum and average of the given arguments
///
/// If any of the arguments is not a number, an
/// error is raised
fn averageAndSum(lua: *Lua) callconv(.c) i32 {
    // `n` is the index of the top of the stack.
    // Because the stack is 1-indexed, this is also the number of items in the stack.
    // At the start of the function, all the items on the stack are the arguments
    // passed to the function.
    const n: usize = @intCast(lua.getTop());

    var sum: Lua.Number = 0;
    // Loop over indexes of the arguments
    for (1..n + 1) |i| {
        // Check if the argument at `i` is a number
        if (!lua.isNumber(@intCast(i))) {
            // Raise an error. `raiseErrorType` is a helper function that makes
            // a nicer looking error message for argument type errors.
            lua.raiseErrorType(@intCast(i), "number");
        }
        // Convert the value at the given index to a number, and add it to the sum
        sum += lua.toNumber(@intCast(i));
    }

    // `pushNumber` takes a number an puts it on the top of the stack

    lua.pushNumber(sum / @as(Lua.Number, @floatFromInt(n))); // Average
    lua.pushNumber(sum); // Sum

    // Now, the two values at the top of the stack are the average, and the sum.

    // By returning `2`, the two values at the top of the stack are
    // returned by the Lua function.
    return 2;
}
