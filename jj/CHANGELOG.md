# Changelog

All notable changes to the jj-ffi project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2025-12-19

### Added

- Initial release of jj-ffi C-compatible FFI wrapper
- Core workspace operations:
  - `jj_workspace_init()` - Initialize new workspace
  - `jj_workspace_open()` - Open existing workspace
  - `jj_workspace_init_colocated()` - Init from git repository
  - `jj_is_jj_workspace()` - Check if path is jj workspace
- Commit operations:
  - `jj_get_commit()` - Get commit by ID
  - `jj_list_changes()` - List recent changes with limit and bookmark filter
- Bookmark operations:
  - `jj_list_bookmarks()` - List all bookmarks (jj's branches)
- File operations:
  - `jj_list_files()` - List files at revision
  - `jj_get_file_content()` - Get file content at revision
- Operation metadata:
  - `jj_get_current_operation()` - Get current operation info
- Memory management functions for all data types
- Complete C header file (`jj_ffi.h`) with documentation
- Comprehensive integration guide (`INTEGRATION.md`)
- Project documentation (`PROJECT.md`)
- Working Zig example (`example.zig`)
- Build scripts (`build_example.sh`, `test_build.sh`)
- Integration with server-zig `build.zig`

### Dependencies

- jj-lib v0.36.0 (pinned for API stability)
- tokio v1 (async runtime for file operations)

### Platform Support

- macOS: Fully supported and tested
- Linux: Should work (untested)
- Windows: Untested

### Known Limitations

- Single-threaded use only (workspace handle not thread-safe)
- Synchronous API (blocks on async jj-lib operations)
- No transaction/write operations (read-only)
- No conflict resolution API
- Limited error detail (string messages only)

### Documentation

- README.md: Quick start and basic usage
- INTEGRATION.md: Comprehensive integration guide for Zig
- PROJECT.md: Architecture and design decisions
- jj_ffi.h: C API reference with inline documentation
- example.zig: Working example demonstrating all features

### Breaking Changes

None (initial release)

## [Unreleased]

### Planned

- Write operations (create commits, modify files)
- Conflict resolution API
- Streaming file API for large files
- Async API support
- Linux and Windows testing
- Performance benchmarks
- Additional examples (web server, CLI tool)

### Under Consideration

- Callbacks for progress reporting
- Transaction API
- Remote operations (push/pull)
- Merge operations
- Rebase operations
