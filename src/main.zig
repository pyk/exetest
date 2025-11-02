const std = @import("std");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var name: []const u8 = "Watson";
    var should_fail = false;
    var greet = false;

    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--greet")) {
            greet = true;
        } else if (std.mem.eql(u8, arg, "--fail")) {
            should_fail = true;
        } else if (std.mem.startsWith(u8, arg, "--name=")) {
            name = arg[7..];
        }
    }

    if (should_fail) {
        std.debug.print("An error occurred.\n", .{});
        return error.CliError;
    }

    if (greet) {
        std.debug.print("Hello, {s}!\n", .{name});
    }

    var stdin_buffer: [1024]u8 = undefined;
    var stdin_file = std.io.getStdIn().reader();
    const bytes_read = try stdin_file.readAll(&stdin_buffer);
    if (bytes_read > 0) {
        std.debug.print("Input: {s}\n", .{stdin_buffer[0..bytes_read]});
    }
}
