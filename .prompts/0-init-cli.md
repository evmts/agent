# Init cli

## Task Definition

Initialize a zig cli app using zig clap.

## Context & Constraints

### Technical Requirements

- **Language/Framework**: Zig - https://ziglang.org/documentation/master/
- **Dependencies**: zig-clap https://github.com/Hejsil/zig-clap
- **Performance**: n/a
- **Compatibility**: n/a

### Business Context

This is a brand new repo that will build an application named plue. This is a git wrapper application modeled after graphite and gitea.

## Detailed Specifications

### Input

n/a

### Expected Output

A working CLI application with:
- Main command that logs "Hello, world!" and exits
- Start subcommand that runs continuously with graceful shutdown on SIGINT/SIGTERM
- Unit tests for both commands
- Proper documentation in CONTRIBUTING.md

### Steps

- Read CLAUDE.md in full to remind yourself of best practices
- Read zig clap readme
- zig fetch to install. We are using stable release
- Read zig clap reference docs https://hejsil.github.io/zig-clap/
- Use GPA as allocator
- Add a single sub command called "start" for now and just make it log and block with a graceful cleanup when we control c. Use web search for best practices here
- For the main command make it log hello world and exit
- Update CONTRIBUTING.md with zig docs, zig std lib docs, zig clap github, and zig clap generated docs
- Add 1 unit test each for both commands you add
- Update claude.md with links to CONTRIBUTING.md and any other important info worth adding. But be brief and concise
- Create atomic emoji conventional commit but only if all tests pass and build is good

### Implementation Details

For the start command signal handling:
```zig
const sigint_action = std.posix.Sigaction{
    .handler = .{ .handler = handleSignal },
    .mask = std.posix.empty_sigset,
    .flags = 0,
};

std.posix.sigaction(std.posix.SIG.INT, &sigint_action, null);
std.posix.sigaction(std.posix.SIG.TERM, &sigterm_action, null);
```

Main.zig structure:
```zig
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var iter = std.process.ArgIterator.init();
    _ = iter.next(); // skip program name
    
    if (iter.next()) |first_arg| {
        if (std.mem.eql(u8, first_arg, "start")) {
            try StartCommand.run(allocator, &iter);
            return;
        }
        // handle help and unknown commands
    }
    
    std.log.info("Hello, world!", .{});
}
```

## Code Style & Architecture

### Design Patterns

- Write idiomatic performant zig according to CLAUDE.md
- Keep file structure flat with all cmds just in commands/ directory
- Make commands easily testable and agnostic to the cli application logic keep all cli specific logic in the main entrypoint
- Commands receive allocator and ArgIterator for flexibility

### Code Organization

```
project/
├── build.zig
├── build.zig.zon  # Package dependencies
├── CLAUDE.md
├── CONTRIBUTING.md
├── src/
│   ├── main.zig
│   ├── commands/
│   │   └── start.zig
```

### Success criteria

All steps completed with pr in production ready state
No hacks or workarounds

## Implementation Summary

**Commit**: f48bf2c - feat: ⚡ Initialize CLI app with zig-clap (Jul 22, 2025)

**What was implemented**:
- Successfully initialized CLI with zig-clap dependency
- Created main.zig with GPA allocator and basic command routing
- Implemented start command with proper signal handling (SIGINT/SIGTERM)
- Added unit tests for both commands
- Created CONTRIBUTING.md with all requested documentation links
- Updated CLAUDE.md with project resources section

**How it went**:
The implementation was successful and followed all requirements. The CLI was structured with a clean separation between the main entry point and individual commands. The start command properly implemented graceful shutdown with signal handlers. Tests were added though the start command test was later skipped when GUI functionality was integrated (commit 21ce987). The project evolved beyond the initial CLI to include a web server and GUI, but the foundation laid in this initial commit remained solid.
