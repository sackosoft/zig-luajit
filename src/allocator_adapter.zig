const std = @import("std");

const max = @alignOf(std.c.max_align_t);

/// Memory allocation function used by Lua instances. This functino acts as an adaptor from the C API to the
/// idiomatic Zig `std.mem.Allocator` type. The implementation provides functionality similar to realloc.
///
/// Arguments:
/// - ud: The opaque pointer passed to lua_newstate
/// - ptr: Pointer to the block being allocated/reallocated/freed
/// - osize: Original size of the block
/// - nsize: New size of the block
///
/// Behavior:
/// - If ptr is NULL, osize must be zero
/// - When nsize is zero, must return NULL and free ptr if osize is non-zero
/// - When nsize is non-zero:
///   * Returns NULL if request cannot be fulfilled
///   * Behaves like malloc if osize is zero
///   * Behaves like realloc if both osize and nsize are non-zero
/// - Lua assumes allocator never fails when osize >= nsize
///
/// From: `void * (*lua_Alloc) (void *ud, void *ptr, size_t osize, size_t nsize);`
/// Refer to: https://www.lua.org/manual/5.1/manual.html#lua_Alloc
pub fn alloc(ud: ?*anyopaque, ptr: ?*anyopaque, osize: usize, nsize: usize) callconv(.C) ?*align(max) anyopaque {
    const allocator: *std.mem.Allocator = @ptrCast(@alignCast(ud.?));
    const aligned_ptr = @as(?[*]align(max) u8, @ptrCast(@alignCast(ptr)));
    if (aligned_ptr) |p| {
        if (nsize != 0) {
            const old_mem = p[0..osize];
            return (allocator.realloc(old_mem, nsize) catch return null).ptr;
        }

        allocator.free(p[0..osize]);
        return null;
    } else {
        // Malloc case
        return (allocator.alignedAlloc(u8, max, nsize) catch return null).ptr;
    }
}
