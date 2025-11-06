const std = @import("std");
const Build = std.Build;
const testing = std.testing;
const Child = std.process.Child;

/// Options for `add` used by user's `build.zig`.
pub const AddOptions = struct {
    /// name of the test target
    name: []const u8,
    /// path to the test source file
    test_file: Build.LazyPath,
    /// the `exetest` build module to import into the test.
    exetest_mod: *Build.Module,
};

/// Register an integration test runnable with the build.
///
/// This creates a test module that imports the `exetest` runtime and
/// produces a `run` step that executes the compiled test binary. It also
/// ensures all build-installed executables are available via `PATH`.
pub fn add(b: *Build, options: AddOptions) *Build.Step.Run {
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

/// Options for `run` controlling I/O, allocator and output limits.
pub const RunOptions = struct {
    argv: []const []const u8,
    allocator: std.mem.Allocator = testing.allocator,
    stdin: ?[]const u8 = null,
    max_output_bytes: usize = 50 * 1024,
};

/// Result returned by `run` with exit info and captured output.
pub const RunResult = struct {
    /// Exit code (0 on success, otherwise process-specific value).
    code: u8,
    /// Termination reason returned by `Child.wait()`.
    term: Child.Term,
    /// Captured stdout bytes.
    stdout: []const u8,
    /// Captured stderr bytes.
    stderr: []const u8,
    /// Allocator used for the captured buffers.
    allocator: std.mem.Allocator,

    pub fn deinit(self: *RunResult) void {
        self.allocator.free(self.stdout);
        self.allocator.free(self.stderr);
    }
};

/// Spawn and run an executable with the given `RunOptions`.
///
/// This is a synchronous helper that spawns the child, collects stdout and
/// stderr up to `max_output_bytes`, waits for termination and returns a
/// `RunResult` with captured output and termination info.
pub fn run(options: RunOptions) !RunResult {
    // Create child process
    var child = Child.init(options.argv, options.allocator);
    child.stdin_behavior = if (options.stdin) |_| .Pipe else .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    // Ensure we attempt to kill the child if this function unwinds
    errdefer {
        _ = child.kill() catch {};
    }

    // Prepare buffers to collect stdout and stderr
    var stdout_buffer: std.ArrayList(u8) = .empty;
    var stderr_buffer: std.ArrayList(u8) = .empty;

    try child.collectOutput(
        options.allocator,
        &stdout_buffer,
        &stderr_buffer,
        options.max_output_bytes,
    );

    // Wait for child termination and include the termination reason in the panic message.
    const term = try child.wait();

    return RunResult{
        .code = if (term == .Exited) term.Exited else 0,
        .term = term,
        .stdout = try stdout_buffer.toOwnedSlice(options.allocator),
        .stderr = try stderr_buffer.toOwnedSlice(options.allocator),
        .allocator = options.allocator,
    };
}
