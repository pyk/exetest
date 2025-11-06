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
    /// Optional working directory for the child process. When null the
    /// child inherits the parent's current working directory.
    cwd: ?[]const u8 = null,
    /// Optional environment map to use for the child process. When null the
    /// child's environment will inherit from the parent process.
    env_map: ?*const std.process.EnvMap = null,
    /// Maximum number of bytes to capture from stdout/stderr.
    max_output_bytes: usize = 50 * 1024,
    /// Maximum number of bytes to write into the child's stdin. If the
    /// provided `stdin` slice is larger, it will be truncated to this size.
    max_stdin_bytes: usize = 64 * 1024,
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
    child.cwd = options.cwd;
    child.env_map = options.env_map;
    child.stdin_behavior = if (options.stdin) |_| .Pipe else .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    // Ensure we attempt to kill the child if this function unwinds
    errdefer {
        _ = child.kill() catch {};
    }

    // If stdin content was provided, write it to the child's stdin pipe and
    // close the pipe so the child sees EOF.
    if (options.stdin) |stdin_bytes| {
        if (child.stdin) |stdin_file| {
            // Determine how many bytes we will actually write (truncate if needed)
            const write_len = if (@as(usize, stdin_bytes.len) < options.max_stdin_bytes)
                @as(usize, stdin_bytes.len)
            else
                options.max_stdin_bytes;

            // Use a small stack buffer for the File.writer
            var buf: [1024]u8 = undefined;
            var writer = stdin_file.writer(&buf);
            const io = &writer.interface;

            // writeAll may return errors from low-level I/O; only write up to write_len
            try io.writeAll(stdin_bytes[0..write_len]);
            // flush to ensure data is sent
            try io.flush();

            // Close the writing end to signal EOF to the child
            stdin_file.close();
            // Mark as closed to avoid double-close in Child.cleanupStreams
            child.stdin = null;
        }
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
