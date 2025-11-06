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
    // helper exe prints OK when no flags provided
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
    // should print each arg on its own line (args[1..])
    try testing.expectEqualStrings("a\nb\n", result.stdout);
    try testing.expectEqual(@as(u8, 0), result.code);
    try testing.expect(result.term == .Exited);
    try testing.expectEqualStrings("", result.stderr);
}

test "run: stdin forwarded" {
    // use system `cat` to echo stdin to stdout
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
    // request the helper to write to stderr
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
