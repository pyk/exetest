const std = @import("std");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var it = try std.process.argsWithAllocator(allocator);
    defer it.deinit();

    var args_list = std.array_list.Managed([]const u8).init(allocator);
    defer args_list.deinit();
    while (it.next()) |arg| {
        try args_list.append(arg);
    }
    const args = args_list.items;

    // detect --stderr, --exit N, --abort and collect positional args (excluding program name)
    var pos_list = std.array_list.Managed([]const u8).init(allocator);
    defer pos_list.deinit();
    var use_stderr = false;
    var i: usize = 1;
    var exit_requested: ?u8 = null;
    var abort_requested = false;
    var print_cwd = false;
    var getenv_name: ?[]const u8 = null;
    while (i < args.len) : (i += 1) {
        const s = args[i];
        if (std.mem.eql(u8, s, "--stderr")) {
            use_stderr = true;
            continue;
        }
        if (std.mem.eql(u8, s, "--abort")) {
            abort_requested = true;
            continue;
        }
        if (std.mem.eql(u8, s, "--print-cwd")) {
            print_cwd = true;
            continue;
        }
        if (std.mem.eql(u8, s, "--getenv")) {
            if (i + 1 >= args.len) {
                std.debug.print("missing getenv name\n", .{});
                std.process.exit(1);
            }
            getenv_name = args[i + 1];
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, s, "--exit")) {
            // next argument must be the exit code
            if (i + 1 >= args.len) {
                std.debug.print("missing exit code\n", .{});
                std.process.exit(1);
            }
            const code_s = args[i + 1];
            // parse as unsigned 8-bit integer
            const parsed = std.fmt.parseInt(u8, code_s, 10) catch {
                std.debug.print("invalid exit code: {s}\n", .{code_s});
                std.process.exit(1);
            };
            exit_requested = parsed;
            i += 1; // skip the numeric argument
            continue;
        }
        try pos_list.append(s);
    }
    const pos = pos_list.items;

    // single writer buffer used for whichever stream we pick
    var buf: [1024]u8 = undefined;
    var writer = if (use_stderr) std.fs.File.stderr().writer(&buf) else std.fs.File.stdout().writer(&buf);
    const io = &writer.interface;

    if (getenv_name) |name| {
        var env_map = std.process.getEnvMap(allocator) catch @panic("fails to get map");
        defer env_map.deinit();
        if (env_map.get(name)) |v| {
            try io.writeAll(v);
        }
        try io.writeAll("\n");
    } else if (print_cwd) {
        const cwd = try std.process.getCwdAlloc(allocator);
        defer allocator.free(cwd);
        try io.writeAll(cwd);
        try io.writeAll("\n");
    } else if (pos.len == 0) {
        try io.writeAll("OK\n");
    } else {
        var j: usize = 0;
        while (j < pos.len) : (j += 1) {
            try io.writeAll(pos[j]);
            try io.writeAll("\n");
        }
    }

    try io.flush();

    // Handle special termination flags after producing output.
    if (abort_requested) {
        // abort will terminate the process with SIGABRT on POSIX.
        std.process.abort();
    }

    if (exit_requested) |code| {
        std.process.exit(code);
    }
}
