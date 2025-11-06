const std = @import("std");
const Build = std.Build;
const testing = std.testing;
const Child = std.process.Child;

pub const AddOptions = struct {
    /// Name of the test target
    name: []const u8,
    /// Path to the test source file
    test_file: Build.LazyPath,
    /// The `exetest` build module to import into the test
    exetest_mod: ?*Build.Module,
};

/// Register new test
pub fn add(b: *Build, options: AddOptions) *Build.Step.Run {
    const exetest_mod = if (options.exetest_mod) |mod|
        mod
    else
        b.dependency("exetest", .{
            .target = b.graph.host,
        }).module("exetest");

    // Create the test module that imports the runtime module
    const test_mod = b.createModule(.{
        .root_source_file = options.test_file,
        .target = b.graph.host,
        .imports = &.{
            .{
                .name = "exetest",
                .module = exetest_mod,
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

/// Options for `run` controlling I/O, allocator, and output limits.
pub const RunOptions = struct {
    /// Argument vector passed to the child process.
    /// The first element is the executable name or path.
    ///
    /// For examples:
    ///
    /// [_][]const u8 {"echo", "hello"}
    /// [_][]const u8 {"/bin/echo", "hello"}
    /// [_][]const u8 {"./zig-out/bin/echo", "hello"}
    ///
    argv: []const []const u8,

    /// Allocator used for any allocations performed by `run` and for
    /// capturing stdout/stderr. Defaults to `std.testing.allocator`, which
    /// enables leak detection and is good for tests to ensure proper
    /// memory management.
    allocator: std.mem.Allocator = testing.allocator,

    /// Optional bytes to write into the child's stdin. When provided the
    /// child's stdin will be a pipe and the bytes will be written then the
    /// write-end closed to signal EOF. If null the child's stdin is ignored.
    stdin: ?[]const u8 = null,

    /// Maximum number of bytes to write into the child's stdin.
    /// Defaults to 64 KiB to avoid excessive memory usage for typical CLI test cases.
    /// If the provided `stdin` slice is larger, it will be truncated to this size.
    max_stdin_bytes: usize = 64 * 1024,

    /// Maximum number of bytes to capture from stdout/stderr. Output beyond
    /// this limit will be discarded.
    max_output_bytes: usize = 64 * 1024,

    /// Optional working directory for the child process.
    /// When non-null the child will be started with this path as its current working directory.
    /// When null, the child inherits the parent's working directory.
    cwd: ?[]const u8 = null,

    /// Optional environment map to use for the child process. If provided
    /// the child will use this `EnvMap` instead of inheriting the parent's
    /// environment. The caller must ensure the provided `EnvMap` remains valid
    /// and unmodified for the entire duration of the child process execution.
    env_map: ?*const std.process.EnvMap = null,
};

/// Result returned by `run` with exit info and captured output.
pub const RunResult = struct {
    /// Exit code returned by the child process.
    /// If the process exited normally, this is the exit code.
    /// If terminated by signal or other reason, this is 0.
    code: u8,

    /// Process termination reason, such as exit or signal, from `Child.wait()`.
    term: Child.Term,

    /// Captured stdout slice. If the child's output exceeds `max_output_bytes`, this will be truncated.
    stdout: []const u8,

    /// Captured stderr bytes. If the child's output exceeds `max_output_bytes`, this will be truncated.
    stderr: []const u8,

    /// Allocator used for the captured buffers.
    allocator: std.mem.Allocator,

    /// Frees the captured output buffers.
    /// Must be called to avoid memory leaks after using `RunResult`.
    pub fn deinit(self: *RunResult) void {
        self.allocator.free(self.stdout);
        self.allocator.free(self.stderr);
    }
};

/// Run an executable synchronously and capture its output.
///
/// Spawns the child process, collects stdout and stderr up to `max_output_bytes`,
/// waits for termination, and returns a `RunResult` with captured output and termination info.
/// Returns an error on spawn, I/O, or wait failure.
/// The caller must call `RunResult.deinit` to free captured output buffers.
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

            var buf: [1024]u8 = undefined;
            var writer = stdin_file.writer(&buf);
            const io = &writer.interface;

            try io.writeAll(stdin_bytes[0..write_len]);
            try io.flush();
            stdin_file.close();

            // Mark as closed to avoid double-close in Child.cleanupStreams
            child.stdin = null;
        }
    }

    // Prepare buffers to collect stdout and stderr
    var stdout_buffer: std.ArrayList(u8) = .empty;
    defer stdout_buffer.deinit(options.allocator);

    var stderr_buffer: std.ArrayList(u8) = .empty;
    defer stderr_buffer.deinit(options.allocator);

    try child.collectOutput(
        options.allocator,
        &stdout_buffer,
        &stderr_buffer,
        options.max_output_bytes,
    );
    const term = try child.wait();

    // Set exit code based on termination reason.
    // If exited normally, use exit code. If killed by signal or other, set to 0.
    const code = switch (term) {
        .Exited => |exit_code| exit_code,
        .Signal => 0,
        .Stopped => 0,
        .Unknown => 0,
    };

    return RunResult{
        .code = code,
        .term = term,
        .stdout = try stdout_buffer.toOwnedSlice(options.allocator),
        .stderr = try stderr_buffer.toOwnedSlice(options.allocator),
        .allocator = options.allocator,
    };
}
