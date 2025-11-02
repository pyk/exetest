const exetest = @import("exetest");
const testing = @import("std").testing;
const std = @import("std");

test "cli greeting and error paths" {
    var cmd = exetest.Command(testing.allocator, "main");
    defer cmd.deinit();

    const result_success = try cmd.addArg("--greet").run();
    defer result_success.deinit();

    try testing.expectEqual(@as(u8, 0), result_success.code);
    try testing.expectEqualStrings("Hello, Watson!\n", result_success.stdout);

    var cmd_fail = exetest.Command(testing.allocator, "main");
    defer cmd_fail.deinit();
    const result_fail = try cmd_fail.addArg("--fail").run();
    defer result_fail.deinit();

    try testing.expectEqual(@as(u8, 1), result_fail.code);
    try testing.expectEqualStrings("An error occurred.\n", result_fail.stderr);
}

test "stdin and multiple args" {
    var cmd = exetest.Command(testing.allocator, "main");
    defer cmd.deinit();

    const args = [_][]const u8{"--name", "Alice"};
    const result = try cmd.addArgs(&args).stdin("Hello from stdin").run();
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.code);
    try testing.expectEqualStrings("Hello, Alice!\nInput: Hello from stdin\n", result.stdout);
}
