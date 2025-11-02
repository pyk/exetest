const std = @import("std");
const testing = std.testing;

const Command = @This();

allocator: std.mem.Allocator,
exe_path: []const u8,
args: std.ArrayList([]const u8),
stdin_data: ?[]const u8,

pub fn create(exe_name: []const u8) Command {
    const gen_mod = @import("exetest_gen");
    const exe_path = std.fs.path.join(
        testing.allocator,
        &.{ gen_mod.exe_dir, exe_name },
    ) catch @panic("OOM");

    return Command{
        .exe_path = exe_path,
    };
}

pub fn deinit(self: *Command) void {
    self.args.deinit();
}

pub fn addArg(self: *Command, value: []const u8) !*Command {
    try self.args.append(value);
    return self;
}

pub fn addArgs(self: *Command, values: []const []const u8) !*Command {
    for (values) |value| {
        try self.args.append(value);
    }
    return self;
}

pub fn stdin(self: *Command, data: []const u8) *Command {
    self.stdin_data = data;
    return self;
}

pub fn run(self: *const Command) !RunResult {
    var child_process = std.process.Child.init(self.args.items, self.allocator);
    child_process.argv = &.{self.exe_path} ++ self.args.items;
    child_process.stdin_behavior = if (self.stdin_data) |_| .Pipe else .Ignore;
    child_process.stdout_behavior = .Pipe;
    child_process.stderr_behavior = .Pipe;

    var process = try child_process.spawn();

    if (self.stdin_data) |data| {
        try process.stdin.?.writeAll(data);
        process.stdin.?.close();
    }

    const stdout_buffer = try process.stdout.?.readToEndAlloc(self.allocator, std.math.maxInt(usize));
    const stderr_buffer = try process.stderr.?.readToEndAlloc(self.allocator, std.math.maxInt(usize));

    const term = try process.wait();

    return RunResult{
        .code = if (term == .Exited) term.Exited else 0,
        .term = term,
        .stdout = stdout_buffer,
        .stderr = stderr_buffer,
        .allocator = self.allocator,
    };
}

pub const RunResult = struct {
    code: u8,
    term: std.process.Child.Term,
    stdout: []const u8,
    stderr: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *RunResult) void {
        self.allocator.free(self.stdout);
        self.allocator.free(self.stderr);
    }
};
