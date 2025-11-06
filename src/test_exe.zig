const std = @import("std");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len <= 1) {
        std.debug.print("OK\n", .{});
        return;
    }

    // Simple, order-insensitive handling of a few flags.
    // We inspect the args slice directly.
    // Supported flags:
    // --print-argv
    // --print-argv-stderr
    // --echo-stdin
    // --exit <code>
    // --spam <total> <chunk>

    var i: usize = 1;
    var exit_code: u8 = 0;
    while (i < args.len) : (i += 1) {
        const s = args[i];
        if (std.mem.eql(u8, s, "--print-argv")) {
            var j: usize = 1;
            while (j < args.len) : (j += 1) {
                const a = args[j];
                std.debug.print("{s}\n", .{a});
            }
            break;
        } else if (std.mem.eql(u8, s, "--print-argv-stderr")) {
            var j: usize = 1;
            while (j < args.len) : (j += 1) {
                const a = args[j];
                std.debug.print("ERR: {s}\n", .{a});
            }
            break;
        } else if (std.mem.eql(u8, s, "--echo-arg")) {
            // echo provided argument (avoid stdin API differences across std versions)
            if (i + 1 >= args.len) {
                std.debug.print("missing echo argument\n", .{});
                std.process.exit(2);
            }
            const data = args[i + 1];
            std.debug.print("{s}", .{data});
            break;
        } else if (std.mem.eql(u8, s, "--exit")) {
            if (i + 1 >= args.len) {
                std.debug.print("missing exit code\n", .{});
                std.process.exit(2);
            }
            const parsed = std.fmt.parseInt(u8, args[i + 1], 10) catch {
                std.debug.print("invalid exit code\n", .{});
                std.process.exit(2);
            };
            exit_code = parsed;
            break;
        } else if (std.mem.eql(u8, s, "--spam")) {
            if (i + 2 >= args.len) {
                std.debug.print("spam missing args\n", .{});
                std.process.exit(2);
            }
            const total = std.fmt.parseInt(usize, args[i + 1], 10) catch {
                std.process.exit(2);
            };
            const chunk = std.fmt.parseInt(usize, args[i + 2], 10) catch {
                std.process.exit(2);
            };
            var remaining = total;
            var out_buf = try allocator.alloc(u8, chunk);
            defer allocator.free(out_buf);
            // fill buffer with 'A' (avoid std.mem.set API differences)
            for (out_buf) |*b| b.* = 'A';
            while (remaining > 0) {
                const to_write = if (remaining < chunk) remaining else chunk;
                std.debug.print("{s}", .{out_buf[0..to_write]});
                remaining -= to_write;
            }
            break;
        } else {
            std.debug.print("unknown flag: {s}\n", .{s});
            std.process.exit(2);
        }
    }

    std.process.exit(exit_code);
}
