const std = @import("std");

pub fn main() !void {
    // If arguments are provided, print them each on their own line prefixed
    // with "ARG: " so tests can inspect forwarded args.
    var args = std.process.args();
    var printed_any = false;
    while (args.next()) |arg| {
        printed_any = true;
        std.debug.print("ARG: {s}\n", .{arg});
    }

    if (!printed_any) {
        std.debug.print("hello from test_exe\n", .{});
    }
}
