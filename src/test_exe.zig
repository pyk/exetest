const std = @import("std");

pub fn main() !void {
    std.debug.print("hello from test_exe\n", .{});
    // var args = std.process.args();

    // var name: []const u8 = "exetest";
    // var should_fail: bool = false;
    // var greet: bool = false;

    // while (args.next()) |arg| {
    //     if (std.mem.eql(u8, arg, "--greet")) {
    //         greet = true;
    //     } else if (std.mem.eql(u8, arg, "--fail")) {
    //         should_fail = true;
    //     } else if (std.mem.startsWith(u8, arg, "--name=")) {
    //         name = arg[7..];
    //     }
    // }

    // if (should_fail) {
    //     std.debug.print("An error occurred.\n", .{});
    //     return error.CliError;
    // }

    // if (greet) {
    //     std.debug.print("Hello, {s}!\n", .{name});
    // }

    // var stdin_buffer: [1024]u8 = undefined;
    // const bytes_read = try std.fs.File.stdin().readAll(&stdin_buffer);
    // if (bytes_read > 0) {
    //     std.debug.print("Input: {s}\n", .{stdin_buffer[0..bytes_read]});
    // }
}
