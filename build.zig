const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("zin", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const example_names = [_][]const u8{ "hello", "todo_api", "basic", "middleware", "subroutes" };
    for (example_names) |example_name| {
        const example_exe = b.addExecutable(.{
            .name = example_name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(b.fmt("examples/{s}.zig", .{example_name})),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "zin", .module = mod },
                },
            }),
        });

        const example_run_cmd = b.addRunArtifact(example_exe);
        example_run_cmd.step.dependOn(b.getInstallStep());
        const example_step = b.step(example_name, b.fmt("Run the {s} example", .{example_name}));
        example_step.dependOn(&example_run_cmd.step);
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}
