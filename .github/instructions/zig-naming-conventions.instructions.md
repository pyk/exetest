---
applyTo: "**/*.zig"
---

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
