const exetest = @import("exetest");
const testing = @import("std").testing;
const std = @import("std");

test "run: empty args" {
    var result = exetest.run("exetest", .{});
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.code);
}

test "run: args forwarded" {
    // When an arg string is provided, it should be forwarded as a single argv element
    // to the child process. The `test_exe` prints each arg as "ARG: {s}\n".
    var result = exetest.run("exetest", .{ .args = "--greet" });
    defer result.deinit();

    // Convert stdout bytes to a slice to check the printed arg line.
    const err_slice = result.stderr.items[0..result.stderr.items.len];
    try testing.expect(std.mem.indexOf(u8, err_slice, "ARG: ") != null);
    try testing.expect(std.mem.indexOf(u8, err_slice, "--greet") != null);
}
