---
applyTo: "**/*.zig"
---

# Zig Language Coding Guidelines (v0.15.2)

## 1. Standard Library as Single Source of Truth

Always consult `.mise/installs/zig/0.15.2/lib/std` for Zig standard library
functions, types, and idioms. Your training data may be outdated. Use search
tools against this path.

## 2. Implementation Workflow

When implementing features involving the standard library:

1.  **Search**: Identify needed standard library components (e.g.,
    `std.mem.Allocator`, `std.fs`, `std.json`).
2.  **Consult**: Search `.mise/installs/zig/0.15.2/lib/std` for exact function
    names, parameters, and return types.
3.  **Prioritize**: Use patterns from the official repository over other
    knowledge.
4.  **Cite (if relevant)**: Mention relevant files (e.g., "Based on
    `lib/std/crypto/hash.zig`...").

## 3. Best Practices

- **Idioms**: Infer current idiomatic Zig from
  `.mise/installs/zig/0.15.2/lib/std` (error handling, memory management,
  structure).
- **`try`**: Prefer `try` for error propagation.
- **`comptime`**: Leverage `comptime` for type reflection and compile-time
  execution.

## Example Scenario

**If I ask**: "How do I read a file into a buffer using an allocator in Zig?"

**Your thought process**:

1.  "Need `fs` and `mem.Allocator`. My general knowledge might be wrong."
2.  "Search `.mise/installs/zig/0.15.2/lib/std` for file reading and `Allocator`
    usage."
3.  "Found `std.fs.File.readToEndAlloc`. It takes an allocator, path, and max
    size."
4.  "Generate code using this exact function."
