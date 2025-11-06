# Project Description

- `exetest` is a Zig library to test CLI apps.
- `exetest` is focus on ergonomics, performance and modularity.
- The target audience is Zig developer, esp CLI builder.

---

# Structure

- `build.zig`: Build script.
- `src/root.zig`: Main module, expose `add`, `run`, `cmd` and `argv` functions.
  All unit tests for the `cmd` and `argv` is in this file.
- `src/test_exe.zig`: Source code of binary to test the `run` function.
- `src/test.zig`: Integration tests, mainly used to test `run` function.

---

# Design

`exetest` is designed to be very simple, it only expose 2 core functions and 2
helper functions:

Core functions:

1. `add`: This function is used in the user's `build.zig`. This is used to
   register test file and test runner.
2. `run`: This function is used in the user's tests. It allows user to test any
   binary installed on their system, including all installed executables in
   their `build.zig` script.

Helper functions:

1. `argv`: This function used to convert tuple literal to `[]const []const u8`.
2. `cmd`: This function used to convert string literal to `[]const []const u8`.

Expected user's flow:

1. User install `exetest` via:

   ```shell
   zig fetch --save=exetest https://github.com/pyk/exetest/archive/${VERSION}.tar.gz
   ```

   This will automatically update their `build.zig.zon` file.

2. User add `exetest` into their dependency:

   ```zig
    const exetest = @import("exetest");

    pub fn build(b: *std.Build) !void {
      // Add test
      const run_test = exetest.add(b, .{
          .name = "integration",
          .test_file = b.path("src/test.zig"),
      });

      const test_step = b.step("test", "Run tests");
      test_step.dependOn(&run_test.step);
    }
   ```

3. User write their test file. For example: `src/test.zig`:

   ```zig
    const std = @import("std");
    const testing = std.testing;
    const exetest = @import("exetest");

    test "ls" {
        const argv = exetest.cmd("ls --help");
        var result = exetest.run(.{ .argv = argv });
        defer result.deinit();
        try testing.expectEqual(@as(u8, 0), result.code);
    }
   ```

4. User run their test: `zig build test`.

---

# Development Workflow

Always consult `.mise/installs/zig/0.15.2/lib/std` for Zig standard library
functions, types, and idioms. Your training data may be outdated. Use search
tools against this path.

- `zig build test --summary all` to run the test.
- `zig build` to run build.
- Always run the test after edits to validate changes.

When implementing features involving the standard library:

1.  **Search**: Identify needed standard library components (e.g.,
    `std.mem.Allocator`, `std.fs`, `std.json`).
2.  **Consult**: Search `.mise/installs/zig/0.15.2/lib/std` for exact function
    names, parameters, and return types.
3.  **Prioritize**: Use patterns from the official repository over other
    knowledge.
4.  **Cite (if relevant)**: Mention relevant files (e.g., "Based on
    `lib/std/crypto/hash.zig`...").

# Zig Naming & Style Conventions

This guide outlines the key naming and style conventions from Zig's `std.fs`
library. Use it to maintain consistency when writing Zig code.

# File Naming

- **Primary Type Files**: `PascalCase.zig` When a file's main purpose is to
  define a single, primary type.
  ```
  // File.zig -> defines `std.fs.File`
  // Dir.zig -> defines `std.fs.Dir`
  ```
- **Utility Files**: `snake_case.zig` For files that provide a collection of
  related functions.
  ```
  // get_app_data_dir.zig
  ```

# Declarations

- **Types (structs, enums, unions)**: `PascalCase`
  ```zig
  const Dir = @This();
  pub const Stat = struct { ... };
  pub const OpenMode = enum { ... };
  ```
- **Error Sets & Values**: `PascalCase` Error sets and the values within them
  use `PascalCase`.
  ```zig
  pub const OpenError = error{
      FileNotFound,
      NotDir,
      AccessDenied,
  };
  // return error.FileNotFound;
  ```
- **Public Functions & Methods**: `camelCase` This is the standard for all
  public, callable behavior.
  ```zig
  pub fn openFile(self: Dir, sub_path: []const u8, ...) !File;
  pub fn getEndPos(self: File) !u64;
  ```
- **Variables, Parameters & Fields**: `snake_case` Always prefer `const` over
  `var`. Applies to local variables, function parameters, and fields within
  structs/unions.

  ```zig
  // Function parameter & local variable
  pub fn init(dest_basename: []const u8, ...) {
      const random_integer = std.crypto.random.int(u64);
  }

  // Struct fields
  const AtomicFile = struct {
      file_writer: File.Writer,
      dest_basename: []const u8,
  };
  ```

- **Enum Fields**: `snake_case`
  ```zig
  pub const OpenMode = enum {
      read_only,
      write_only,
      read_write,
  };
  ```
- **Constants**: `snake_case` For exported, package-level constant values.
  ```zig
  pub const default_mode = 0o755;
  pub const sep = '/';
  ```

# General Style

- **Options Structs**: For functions with several arguments (especially boolean
  flags), use a dedicated `Options` struct to improve readability. This pattern
  is used extensively.

  ```zig
  pub const OpenOptions = struct {
      access_sub_paths: bool = true,
      iterate: bool = false,
      no_follow: bool = false,
  };

  pub fn openDir(self: Dir, sub_path: []const u8, options: OpenOptions) !Dir;
  ```

- **Type Aliases**: Use `PascalCase` for type aliases, consistent with other
  type naming.

  ```zig
  pub const Handle = posix.fd_t;
  pub const Mode = posix.mode_t;
  ```

- **Doc comments**: All exported members and all struct fields must have doc
  comments. Doc comments should be short and technical. Use simple words and
  expand any missing technical detail. Do not use em dashes or semicolons.
  Examples below show the allowed style.

  ```zig
  // Good: technical and short
  /// File is a wrapper for an open file descriptor
  pub const File = struct {
      /// The underlying file descriptor
      fd: posix.fd_t,
  };

  // Expand missing detail when needed
  /// Reads up to `len` bytes from the file into `buf`
  /// Returns the number of bytes read or an error
  pub fn read(self: *File, buf: []u8) !usize;

  // Avoid complex words and punctuation like em dash and semicolon
  /// Open a file for reading
  pub fn open(path: []const u8) !File;
  ```
