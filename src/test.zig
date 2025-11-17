const std = @import("std");
const builtin = @import("builtin");
const testing = std.testing;
const cmdtest = @import("cmdtest");

test "run: echo" {
    const argv = &[_][]const u8{ "echo", "hello" };
    var result = try cmdtest.run(.{ .argv = argv });
    defer result.deinit();

    try testing.expectEqualStrings("hello\n", result.stdout);
    try testing.expectEqual(@as(u8, 0), result.code);
    try testing.expect(result.term == .Exited);
    try testing.expectEqualStrings("", result.stderr);
}

test "run: no args" {
    const argv = &[_][]const u8{"cmdtest"};
    var result = try cmdtest.run(.{ .argv = argv });
    defer result.deinit();

    try testing.expectEqualStrings("OK\n", result.stdout);
    try testing.expectEqual(@as(u8, 0), result.code);
    try testing.expect(result.term == .Exited);
    try testing.expectEqualStrings("", result.stderr);
}

test "run: single arg forwarded" {
    const argv = &[_][]const u8{ "cmdtest", "one" };
    var result = try cmdtest.run(.{ .argv = argv });
    defer result.deinit();

    try testing.expectEqualStrings("one\n", result.stdout);
    try testing.expectEqual(@as(u8, 0), result.code);
    try testing.expect(result.term == .Exited);
    try testing.expectEqualStrings("", result.stderr);
}

test "run: multiple args forwarded" {
    const argv = &[_][]const u8{ "cmdtest", "a", "b" };
    var result = try cmdtest.run(.{ .argv = argv });
    defer result.deinit();

    try testing.expectEqualStrings("a\nb\n", result.stdout);
    try testing.expectEqual(@as(u8, 0), result.code);
    try testing.expect(result.term == .Exited);
    try testing.expectEqualStrings("", result.stderr);
}

test "run: stdin forwarded" {
    const argv = &[_][]const u8{"cat"};
    const stdin_data = "line1\nline2\n";
    var result = try cmdtest.run(.{ .argv = argv, .stdin = stdin_data });
    defer result.deinit();

    try testing.expectEqualStrings(stdin_data, result.stdout);
    try testing.expectEqual(@as(u8, 0), result.code);
    try testing.expect(result.term == .Exited);
    try testing.expectEqualStrings("", result.stderr);
}

test "run: stdout/stderr capture" {
    const argv = &[_][]const u8{ "cmdtest", "--stderr", "errdata" };
    var result = try cmdtest.run(.{ .argv = argv });
    defer result.deinit();

    try testing.expectEqualStrings("", result.stdout);
    try testing.expectEqualStrings("errdata\n", result.stderr);
    try testing.expectEqual(@as(u8, 0), result.code);
    try testing.expect(result.term == .Exited);
}

test "run: stdin truncation" {
    const argv = &[_][]const u8{"cat"};

    // create a payload of 4 KiB of 'A'
    const total: usize = 4 * 1024;
    var sbuf: [4096]u8 = undefined;
    var i: usize = 0;
    while (i < total) : (i += 1) sbuf[i] = 'A';
    const payload = sbuf[0..total];

    const limit: usize = 1024; // 1 KiB
    var result = try cmdtest.run(.{
        .argv = argv,
        .stdin = payload,
        .max_stdin_bytes = limit,
    });
    defer result.deinit();

    // Expect the `cat` to echo only the first `limit` bytes
    try testing.expectEqualStrings(@as([]const u8, payload[0..limit]), result.stdout);
    try testing.expectEqual(@as(u8, 0), result.code);
    try testing.expect(result.term == .Exited);
    try testing.expectEqualStrings("", result.stderr);
}

test "run: non-zero exit code" {
    const argv = &[_][]const u8{ "cmdtest", "--exit", "42" };
    var result = try cmdtest.run(.{ .argv = argv });
    defer result.deinit();

    try testing.expectEqual(@as(u8, 42), result.code);
    try testing.expect(result.term == .Exited);
}

test "run: terminated by signal" {
    const argv = &[_][]const u8{ "cmdtest", "--abort" };
    var result = try cmdtest.run(.{ .argv = argv });
    defer result.deinit();

    // Term should indicate a signal (not Exited)
    try testing.expect(result.term != .Exited);
}

test "run: executable not found" {
    const missing = "cmdtest-missing-please-12345";
    const argv = &[_][]const u8{missing};

    // We expect an error when attempting to run a non-existent executable.
    const run_err = cmdtest.run(.{ .argv = argv });
    if (run_err) |r| {
        // Unexpected success: deinit and fail
        var tmp = r;
        defer tmp.deinit();
        try testing.expect(false);
    } else |err| {
        try testing.expectEqual(error.FileNotFound, err);
    }
}

test "run: with cwd" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    const cwd = try std.process.getCwdAlloc(testing.allocator);
    defer testing.allocator.free(cwd);

    const argv = &[_][]const u8{ "cmdtest", "--print-cwd" };
    var result = try cmdtest.run(.{
        .argv = argv,
        .cwd = tmp_path,
    });
    defer result.deinit();

    // Expect the child to print its current working directory matching expected_dir
    const expected_with_nl = try std.fmt.allocPrint(testing.allocator, "{s}\n", .{tmp_path});
    defer testing.allocator.free(expected_with_nl);

    try testing.expectEqualStrings(expected_with_nl, result.stdout);
    try testing.expectEqual(@as(u8, 0), result.code);
    try testing.expect(result.term == .Exited);
}

test "run: with env_map" {
    // Build an EnvMap and insert a test variable.
    var env = std.process.EnvMap.init(testing.allocator);
    defer env.deinit();

    try env.put("cmdtest_VAR", "hello-env");

    const argv = &[_][]const u8{ "cmdtest", "--getenv", "cmdtest_VAR" };
    var result = try cmdtest.run(.{
        .argv = argv,
        .env_map = &env,
    });
    defer result.deinit();

    try testing.expectEqualStrings("hello-env\n", result.stdout);
}

// test "spawn: interactive mode" {
//     const argv = &[_][]const u8{ "cmdtest", "--exit", "42" };
//     var proc = try cmdtest.spawn(.{ .argv = argv });
//     defer proc.deinit();

//     try proc.write("PING\n"); // I expect this to be fail as process exit with 42 as code
//     try proc.expectStdout("TEST");

//     try proc.write("ECHO works\n");
//     try testing.expectEqualStrings("works", try proc.readLineFromStdout());

//     try proc.write("EXIT\n");

//     const term = try proc.child.wait();
//     try testing.expectEqual(@as(u8, 0), term.Exited);
// }

test "write: running process that accepts stdin" {
    const argv = &[_][]const u8{"cat"};
    var proc = try cmdtest.spawn(.{ .argv = argv });
    defer proc.deinit();

    // This write should succeed without error.
    try proc.write("data\n");
    try proc.expectStdout("data");
}

test "write: process confirmed exited" {
    const argv = &[_][]const u8{ "echo", "42" };
    var proc = try cmdtest.spawn(.{ .argv = argv });
    defer proc.deinit();
    _ = try proc.child.wait();
    try testing.expectError(error.ProcessExited, proc.write("data\n"));
}

test "write: running process that ignores stdin" {
    const argv = &[_][]const u8{ "sleep", "1" };
    var proc = try cmdtest.spawn(.{ .argv = argv });
    defer proc.deinit();
    try proc.write("this is ignored\n");
}

test "write: process died unexpectedly" {
    // NOTE: skipped for now, this race condition is known issue
    if (builtin.is_test) return error.SkipZigTest;

    const argv = &[_][]const u8{"ls"};
    var proc = try cmdtest.spawn(.{ .argv = argv });
    defer proc.deinit();
    try testing.expectError(error.ProcessExited, proc.write("data\n"));
}

test "readLineFromStdout: happy path" {
    const argv = &[_][]const u8{ "cmdtest", "--interactive" };
    var proc = try cmdtest.spawn(.{ .argv = argv });
    defer proc.deinit();

    try proc.write("PING\n");
    try testing.expectEqualStrings("PONG", try proc.readLineFromStdout());
}

test "readLineFromStdout: multiple lines" {
    const argv = &[_][]const u8{ "cmdtest", "--interactive" };
    var proc = try cmdtest.spawn(.{ .argv = argv });
    defer proc.deinit();

    try proc.write("ECHO line one\n");
    try testing.expectEqualStrings("line one", try proc.readLineFromStdout());

    try proc.write("ECHO line two\n");
    try testing.expectEqualStrings("line two", try proc.readLineFromStdout());
}

test "readLineFromStdout: handles CRLF endings" {
    const argv = &[_][]const u8{ "cmdtest", "--interactive" };
    var proc = try cmdtest.spawn(.{ .argv = argv });
    defer proc.deinit();

    try proc.write("ECHO line with cr\r\n");
    try testing.expectEqualStrings("line with cr", try proc.readLineFromStdout());
}

test "readLineFromStdout: empty line" {
    const argv = &[_][]const u8{ "cmdtest", "--interactive" };
    var proc = try cmdtest.spawn(.{ .argv = argv });
    defer proc.deinit();

    try proc.write("ECHO \n");
    try testing.expectEqualStrings("", try proc.readLineFromStdout());
}

test "readLineFromStdout: process exited before read" {
    const argv = &[_][]const u8{ "echo", "ok" };
    var proc = try cmdtest.spawn(.{ .argv = argv });
    defer proc.deinit();

    // Wait for the process to fully exit. Its stdout pipe will be closed.
    _ = try proc.child.wait();

    // Attempting to read from a closed pipe should fail
    try testing.expectError(error.ProcessExited, proc.readLineFromStdout());
}

// test "readLineFromStdout: child writes no newline" {
//     // `printf` is a good tool for writing output without a trailing newline
//     const argv = &[_][]const u8{ "printf", "no-newline" };
//     var proc = try cmdtest.spawn(.{ .argv = argv });
//     defer proc.deinit();

//     // The read will consume "no-newline", hit EOF, and since it never found a
//     // '\n' delimiter, it will return an error (EndOfStream), which our
//     // function maps to ReadFailed.
//     try testing.expectError(error.ReadFailed, proc.readLineFromStdout());
// }
