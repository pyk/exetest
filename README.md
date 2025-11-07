### cmdtest

CLI testing for Zig.

### Installation

1. Fetch the latest release:

   ```shell
   zig fetch --save=cmdtest https://github.com/pyk/cmdtest/archive/v0.2.0.tar.gz
   ```

   This updates `build.zig.zon`.

2. Write your test file. Example: `test/mycli.zig`.

   ```zig
    const std = @import("std");
    const cmdtest = @import("cmdtest");
    const testing = std.testing;

    test "via exe name" {
        const argv = &[_][]const u8{"mycli"};
        var result = try cmdtest.run(.{ .argv = argv });
        defer result.deinit();

        try testing.expectEqualStrings("project-exe\n", result.stderr);
    }

    test "via path" {
        const argv = &[_][]const u8{"./zig-out/bin/mycli"};
        var result = try cmdtest.run(.{ .argv = argv });
        defer result.deinit();

        try testing.expectEqualStrings("project-exe\n", result.stderr);
    }
   ```

3. Register the test in `build.zig`:

   ```zig
    const std = @import("std");
    const cmdtest = @import("cmdtest");

    pub fn build(b: *std.Build) void {
        const target = b.standardTargetOptions(.{});

        // Your CLI
        const cli = b.addExecutable(.{
            .name = "mycli",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/main.zig"),
                .target = target,
            }),
        });
        b.installArtifact(cli);

        // Register new test
        const cli_test = cmdtest.add(b, .{
            .name = "mycli",
            .test_file = b.path("test/mycli.zig"),
        });

        const test_step = b.step("test", "Run tests");
        test_step.dependOn(&cli_test.step);
    }
   ```

4. Run the tests:

   ```shell
   zig build test --summary all
   ```

See minimal Zig project
[cmdtest-example](https://github.com/pyk/cmdtest-example).

### Usage

There are only 2 functions:

- `add(b, options)` registers a CLI test step in `build.zig`. `zig build test`
  will run the tests.
- `run(options)` spawns a child process, captures stdout and stderr (up to a
  limit), waits for the child to finish, and returns a `RunResult`.

Basic run and stdout assertion:

```zig
const std = @import("std");
const cmdtest = @import("cmdtest");
const testing = std.testing;

test "echo" {
    const argv = &[_][]const u8{"echo", "hello"};
    var result = try cmdtest.run(.{ .argv = argv });
    defer result.deinit();

    try testing.expectEqualStrings("hello\n", result.stdout);
}
```

Write to stdin and capture stdout:

```zig
const std = @import("std");
const cmdtest = @import("cmdtest");
const testing = std.testing;

test "cat" {
    const argv = &[_][]const u8{"cat"};
    const input = "a\nb\n";
    var result = try cmdtest.run(.{ .argv = argv, .stdin = input });
    defer result.deinit();

    try testing.expectEqualStrings(input, result.stdout);
}
```

Limit how many stdin bytes are sent:

```zig
const payload = large_slice; // some []const u8
var result = try cmdtest.run(.{
  .argv = argv,
  .stdin = payload,
  .max_stdin_bytes = 1024, // truncate to 1 KiB
});
defer result.deinit();
```

And you can do much more:

- Automatically discover built artifacts.
- Capture `stderr` output.
- Limit how much output is captured.
- Run with a custom working directory.
- Run with a custom environment map.
- Handle exit status and signals.
- Detect spawn errors.

See [src/test_exe.zig](./src/test_exe.zig).

Some additional notes about the usage of `allocator`:

- `run` uses `testing.allocator` by default.
- You can pass a different allocator in `RunOptions.allocator` to control where
  captured buffers are allocated.

### Development

Install the Zig toolchain via mise (optional):

```shell
mise trust
mise install
```

Run tests:

```bash
zig build test --summary all
```

Build library:

```bash
zig build
```

### License

See [LICENSE](./LICENSE).
