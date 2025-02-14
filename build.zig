const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const gen_exe = b.addExecutable(.{
        .name = "wasm_trampoline_codegen",
        .root_source_file = b.path("src/js_codegen.zig"),
        .target = b.host,
        .optimize = optimize,
    });
    const run_gen_exe = b.addRunArtifact(gen_exe);
    run_gen_exe.addArg("src/codegen.zig");
    run_gen_exe.addArg("src");
    b.default_step.dependOn(&run_gen_exe.step);

    const lib = b.addExecutable(.{
        .name = "wasm_trampoline",
        .root_source_file = b.path("src/root.zig"),
        .target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding }),
        .optimize = optimize,
    });
    lib.entry = .disabled;
    lib.rdynamic = true;
    b.installArtifact(lib);

    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
