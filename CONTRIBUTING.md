# Contributing to Plue

## Development Resources

### Zig Documentation
- [Zig Language Documentation](https://ziglang.org/documentation/master/) - Official Zig documentation
- [Zig Standard Library](https://ziglang.org/documentation/master/std/) - Standard library reference

### Dependencies
- [zig-clap GitHub](https://github.com/Hejsil/zig-clap) - Command line argument parser
- [zig-clap Generated Docs](https://hejsil.github.io/zig-clap/) - API reference documentation

## Development Setup

1. Install Zig 0.14.1 or later
2. Clone the repository
3. Run `zig build` to build the project
4. Run `zig build test` to run tests
5. Run `zig build run` to run the application

## Code Standards

Follow the coding standards defined in `CLAUDE.md`, including:
- Single responsibility functions
- Memory-conscious allocation patterns
- Tests included in source files
- Immediate build verification after changes

## Build Commands

- `zig build` - Build the project
- `zig build test` - Run all tests
- `zig build run` - Run the application
- `zig build run -- [args]` - Run with arguments