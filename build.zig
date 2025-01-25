const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const luajit_build_dep = b.dependency("luajit_build", .{ .target = target, .optimize = optimize, .link_as = .static });
    const luajit_build = luajit_build_dep.module("luajit-build");

    const lib_mod = b.addModule("luajit", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addStaticLibrary(.{
        .name = "luajit",
        .root_module = lib_mod,
    });
    lib.root_module.addImport("c", luajit_build);

    b.installArtifact(lib);

    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
