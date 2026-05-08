# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## [v3.0.0] - 2026-05-08

Upgrade from Zig 0.15.2 to Zig 0.16.0 across library and examples.

### Changed

- Upgraded `zig-luajit-build` dependency from 1.1.6 to 1.1.8 to adopt Zig 0.16.0 changes.
- Changed API for `Lua.dump()`, `Lua.load()` and all `prettyPrint()` functions to adopt new `std.Io.Reader` and
  `std.Io.Writer` interfaces. All references to the now deleted  `std.io.AnyReader` and `std.io.AnyWriter` are removed.
- Changed API for `HookMask` struct, it is now zeroed by default instead of containing uninitialized memory.
- Updated all example programs to 0.16.0 and removed unnecessary README.md files in the examples directory.


## [v2.0.0] - 2025-05-21

### Fixed

- Corrected a logic error causing the `Lua.checkArgument()` function to incorrectly error on a passing condition.
    - Refer to [bug: checkArgument has inverse logic #17](https://github.com/sackosoft/zig-luajit/issues/17)

[v2.0.0]: https://github.com/sackosoft/zig-luajit/compare/v2.0.1...v3.0.0
[v2.0.0]: https://github.com/sackosoft/zig-luajit/compare/v1.5.4...v2.0.0
[v1.5.4]: https://github.com/sackosoft/zig-luajit/releases/tag/v1.5.4
