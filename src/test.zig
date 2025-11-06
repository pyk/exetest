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
