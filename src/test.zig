const exetest = @import("exetest");
const testing = @import("std").testing;
const std = @import("std");

test "run: empty args" {
    var result = exetest.run("exetest", .{});
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.code);
}
