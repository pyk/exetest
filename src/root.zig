const std = @import("std");
const fs = std.fs;
const testing = std.testing;
const Child = std.process.Child;
const Writer = std.Io.Writer;
const Reader = std.Io.Reader;
const ArrayList = std.ArrayList;

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

/// Options for `spawn` controlling the child process environment.
pub const SpawnOptions = struct {
    argv: []const []const u8,
    allocator: std.mem.Allocator = testing.allocator,
    cwd: ?[]const u8 = null,
    env_map: ?*const std.process.EnvMap = null,
};

/// Manages a long-running, interactive child process for testing.
pub const InteractiveProcess = struct {
    const Self = @This();

    child: Child,
    pid: Child.Id,
    stdout_buffer: [1024]u8 = undefined,
    stdin_buffer: [1024]u8 = undefined,
    stderr_buffer: [1024]u8 = undefined,

    /// Cleans up resources and ensures the child process is terminated.
    /// This should always be called, typically with `defer`.
    pub fn deinit(self: *Self) void {
        if (self.child.stdin) |stdin_file| {
            stdin_file.close();
            self.child.stdin = null;
        }
        _ = self.child.wait() catch {};
    }

    pub const WriteError = error{
        // This means process already exited or child.stdin is closed
        ProcessExited,
        // This means something wrong when writing to stdin
        WriteFailed,
    };

    pub const ReadStdoutError = error{
        // This means process already exited
        ProcessExited,
        // This means something wrong when reading from stdout
        ReadFailed,
    };

    /// Writes bytes to the child process's stdin.
    ///
    /// This method attempts to write all bytes and flush the underlying pipe.
    /// If the child's stdin is not available (closed or process exited) this
    /// returns `error.ProcessExited`. Other I/O failures return `error.WriteFailed`.
    ///
    /// Notes:
    /// - Writing to a child's stdin only writes into the OS pipe buffer. It does
    ///   not guarantee the child will read or consume those bytes. For example,
    ///   a process that intentionally ignores stdin (or never reads from it) may
    ///   still make `write` succeed because the bytes are buffered by the OS.
    /// - Short-lived commands may introduce a timing/race condition: a command
    ///   might exit quickly around the same time as a write attempt. Depending
    ///   on timing, `write` may succeed because the write occurred before the
    ///   kernel noticed the process exit (or due to buffering), or it may return
    ///   `error.ProcessExited`. As a result, tests asserting a deterministic
    ///   `error.ProcessExited` for short-lived commands can be flaky and may
    ///   need to be skipped for reliability.
    pub fn write(self: *Self, bytes: []const u8) WriteError!void {
        const stdin_file = self.child.stdin orelse return error.ProcessExited;
        var stdin_writer = stdin_file.writer(&self.stdin_buffer);
        var stdin = &stdin_writer.interface;
        stdin.writeAll(bytes) catch return error.WriteFailed;
        stdin.flush() catch return error.WriteFailed;
    }

    /// Reads from the child's stdout until a newline is found or the buffer is full.
    /// The returned slice does not include the newline character.
    pub fn readLineFromStdout(self: *Self) ReadStdoutError![]const u8 {
        const stdout_file = self.child.stdout orelse return error.ProcessExited;
        var stdout_reader = stdout_file.reader(&self.stdout_buffer);
        var stdout = &stdout_reader.interface;
        const line = stdout.takeDelimiter('\n') catch return error.ReadFailed;
        // Handle potential CR on Windows if the child outputs CRLF
        const trimmed = std.mem.trimEnd(u8, line.?, "\r");
        return trimmed;
    }

    /// Reads from the child's stderr until a newline is found.
    pub fn readLineFromStderr(self: *Self) ![]const u8 {
        const stderr_file = self.child.stderr orelse return error.MissingStderr;
        var stderr_reader = stderr_file.reader(&self.stderr_buffer);
        var stderr = &stderr_reader.interface;
        const line = try stderr.takeDelimiter('\n') orelse return error.EmptyLine;
        // Handle potential CR on Windows if the child outputs CRLF
        const trimmed = std.mem.trimEnd(u8, line, "\r");
        return trimmed;
    }

    // TODO: add expectStdout
    // TODO: add expectStderr

    pub fn expectStdout(self: *Self, expected: []const u8) !void {
        var stderr_writer = fs.File.stdout().writer(&self.stderr_buffer);
        var stderr = &stderr_writer.interface;

        const actual = self.readLineFromStdout() catch |err| {
            try stderr.print("\n\n--- Test Expectation Failed ---\n", .{});
            try stderr.print("Expected to read from stdout:\n{s}\n\n", .{expected});
            try stderr.print("But the read operation failed with error: {any}\n", .{err});
            try stderr.print("---------------------------------\n\n", .{});
            try stderr.flush();
            return err;
        };

        std.testing.expectEqualStrings(expected, actual) catch |err| {
            try stderr.print("\n\n--- HELLO ---\n", .{});
            return err;
        };
    }
};

/// Spawns an executable for interactive testing.
///
/// Returns an `InteractiveProcess` object to manage the child process's
/// lifecycle and I/O. The caller is responsible for calling `deinit()`
/// on the returned object to ensure cleanup.
pub fn spawn(options: SpawnOptions) !InteractiveProcess {
    var child = Child.init(options.argv, options.allocator);
    child.cwd = options.cwd;
    child.env_map = options.env_map;

    // We need pipes for all streams to interact with them
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    return InteractiveProcess{ .child = child, .pid = child.id };
}
