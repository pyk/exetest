const std = @import("std");
const testing = std.testing;
const exetest = @import("exetest");

test "run: echo" {
    const argv = &[_][]const u8{ "echo", "hello" };
    var result = try exetest.run(.{ .argv = argv });
    defer result.deinit();

    try testing.expectEqualStrings("hello\n", result.stdout);
    try testing.expectEqual(@as(u8, 0), result.code);
    try testing.expect(result.term == .Exited);
    try testing.expectEqualStrings("", result.stderr);
}

test "run: no args" {
    const argv = &[_][]const u8{"exetest"};
    var result = try exetest.run(.{ .argv = argv });
    defer result.deinit();

    try testing.expectEqualStrings("OK\n", result.stdout);
    try testing.expectEqual(@as(u8, 0), result.code);
    try testing.expect(result.term == .Exited);
    try testing.expectEqualStrings("", result.stderr);
}

test "run: single arg forwarded" {
    const argv = &[_][]const u8{ "exetest", "one" };
    var result = try exetest.run(.{ .argv = argv });
    defer result.deinit();

    try testing.expectEqualStrings("one\n", result.stdout);
    try testing.expectEqual(@as(u8, 0), result.code);
    try testing.expect(result.term == .Exited);
    try testing.expectEqualStrings("", result.stderr);
}

test "run: multiple args forwarded" {
    const argv = &[_][]const u8{ "exetest", "a", "b" };
    var result = try exetest.run(.{ .argv = argv });
    defer result.deinit();

    try testing.expectEqualStrings("a\nb\n", result.stdout);
    try testing.expectEqual(@as(u8, 0), result.code);
    try testing.expect(result.term == .Exited);
    try testing.expectEqualStrings("", result.stderr);
}

test "run: stdin forwarded" {
    const argv = &[_][]const u8{"cat"};
    const stdin_data = "line1\nline2\n";
    var result = try exetest.run(.{ .argv = argv, .stdin = stdin_data });
    defer result.deinit();

    try testing.expectEqualStrings(stdin_data, result.stdout);
    try testing.expectEqual(@as(u8, 0), result.code);
    try testing.expect(result.term == .Exited);
    try testing.expectEqualStrings("", result.stderr);
}

test "run: stdout/stderr capture" {
    const argv = &[_][]const u8{ "exetest", "--stderr", "errdata" };
    var result = try exetest.run(.{ .argv = argv });
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
    var result = try exetest.run(.{
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
    const argv = &[_][]const u8{ "exetest", "--exit", "42" };
    var result = try exetest.run(.{ .argv = argv });
    defer result.deinit();

    try testing.expectEqual(@as(u8, 42), result.code);
    try testing.expect(result.term == .Exited);
}

test "run: terminated by signal" {
    const argv = &[_][]const u8{ "exetest", "--abort" };
    var result = try exetest.run(.{ .argv = argv });
    defer result.deinit();

    // Term should indicate a signal (not Exited)
    try testing.expect(result.term != .Exited);
}

test "run: executable not found" {
    const missing = "exetest-missing-please-12345";
    const argv = &[_][]const u8{missing};

    // We expect an error when attempting to run a non-existent executable.
    const run_err = exetest.run(.{ .argv = argv });
    if (run_err) |r| {
        // Unexpected success: deinit and fail
        var tmp = r;
        defer tmp.deinit();
        try testing.expect(false);
    } else |err| {
        // Got an error as expected. Nothing more to assert (error kinds vary by platform).
        // Print the error (to reference it) and consider this test successful
        // because an error was expected.
        std.debug.print("spawn error: {any}\n", .{err});
        try testing.expect(true);
    }
}

test "run: with cwd" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const tmp_path = try tmp.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    const cwd = try std.process.getCwdAlloc(testing.allocator);
    defer testing.allocator.free(cwd);

    const argv = &[_][]const u8{ "exetest", "--print-cwd" };
    var result = try exetest.run(.{
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
