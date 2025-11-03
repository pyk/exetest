const std = @import("std");
const Build = std.Build;
const testing = std.testing;

const Options = struct {
    name: []const u8,
    test_file: Build.LazyPath,
    exetest_mod: *Build.Module,
};

pub fn add(b: *Build, options: Options) *Build.Step.Run {
    // Create the test module that imports the runtime module
    const test_mod = b.createModule(.{
        .root_source_file = options.test_file,
        .target = b.graph.host,
        .imports = &.{
            .{
                .name = "exetest",
                .module = options.exetest_mod,
            },
        },
    });

    // Create the test executable compilation step
    const test_exe = b.addTest(.{
        .name = options.name,
        .root_module = test_mod,
    });
    const run_test_exe = b.addRunArtifact(test_exe);

    // IMPORTANT: Make sure all exe are installed first
    run_test_exe.step.dependOn(b.getInstallStep());

    const original_path = b.graph.env_map.get("PATH") orelse "";
    const path = b.fmt("{s}{c}{s}", .{
        b.exe_dir,
        std.fs.path.delimiter,
        original_path,
    });

    run_test_exe.setEnvironmentVariable("PATH", path);

    return run_test_exe;
}

pub const RunOptions = struct {
    allocator: std.mem.Allocator = testing.allocator,
    args: ?[]const u8 = null,
    stdin: ?[]const u8 = null,
    max_output_bytes: usize = 50 * 1024,
};

pub const RunResult = struct {
    code: u8,
    term: std.process.Child.Term,
    stdout: std.ArrayList(u8),
    stderr: std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub fn deinit(self: *RunResult) void {
        self.stdout.deinit(self.allocator);
        self.stderr.deinit(self.allocator);
    }
};

pub fn run(exe_name: []const u8, options: RunOptions) RunResult {
    // Create child process
    // Build argv with only the executable name when args is null, otherwise include the provided arg.
    var single_argv: [1][]const u8 = .{exe_name};
    var double_argv: [2][]const u8 = .{ exe_name, options.args orelse "" };
    const argv_ptr: [][]const u8 = if (options.args) |_| double_argv[0..2] else single_argv[0..1];
    var child = std.process.Child.init(argv_ptr, options.allocator);
    child.stdin_behavior = if (options.stdin) |_| .Pipe else .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    // Set PATH
    var env_map = std.process.getEnvMap(options.allocator) catch @panic("OOM");
    defer env_map.deinit();
    const path = env_map.get("PATH") orelse "(PATH empty)";

    // Spawn the child process and provide more context on failures
    child.spawn() catch |err| std.debug.panic(
        \\failed to spawn executable '{s}' with args '{s}': {any}
        \\PATH: {s}
        \\Hint: ensure the executable is present in PATH or the provided name is correct.
    ,
        .{
            exe_name,
            (options.args orelse ""),
            err,
            path,
        },
    );

    // Ensure we attempt to kill the child if this function unwinds
    errdefer {
        _ = child.kill() catch |err| std.debug.panic(
            \\failed to kill child process for executable '{s}': {any}
            \\PATH: {s}
        , .{ exe_name, err, path });
    }

    // Prepare buffers to collect stdout and stderr
    var stdout_buffer: std.ArrayList(u8) = .empty;
    var stderr_buffer: std.ArrayList(u8) = .empty;

    child.collectOutput(
        options.allocator,
        &stdout_buffer,
        &stderr_buffer,
        options.max_output_bytes,
    ) catch |err| std.debug.panic(
        \\failed collecting output from executable '{s}' (args='{s}'): {any}
        \\Stdout length: {d}
        \\Stderr length: {d}
        \\PATH: {s}
        \\Hint: increase max_output_bytes if output was truncated or inspect the program for excessive output.
    ,
        .{
            exe_name,
            (options.args orelse ""),
            err,
            stdout_buffer.items.len,
            stderr_buffer.items.len,
            path,
        },
    );

    // Wait for child termination and include the termination reason in the panic message.
    const term = child.wait() catch |err| std.debug.panic(
        \\failed waiting for executable '{s}' to terminate (args='{s}'): {any}
        \\PATH: {s}
        \\Hint: the process may have failed to start or the system ran out of resources
    , .{
        exe_name,
        (options.args orelse ""),
        err,
        path,
    });

    return RunResult{
        .code = if (term == .Exited) term.Exited else 0,
        .term = term,
        .stdout = stdout_buffer,
        .stderr = stderr_buffer,
        .allocator = options.allocator,
    };
}
