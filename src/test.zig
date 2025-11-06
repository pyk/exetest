const std = @import("std");
const testing = std.testing;
const exetest = @import("exetest");

test "run: echo" {
    const argv = &[_][]const u8{ "echo", "hello" };
    var result = try exetest.run(.{ .argv = argv });
    defer result.deinit();

    try testing.expectEqualStrings("hello\n", result.stdout);
}
