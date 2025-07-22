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

### Steps

- Read CLAUDE.md in full to remind yourself of best practices
- Read zig clap readme
- zig fetch to install. We are using stable release
- Read zig clap reference docs https://hejsil.github.io/zig-clap/
- Use GPA as allocator
- Add a single sub command called "start" for now and just make it log and block with a gracefull cleanup when we control c. Use web search for best practices here
- For the main command make it log hello world and exit
- Update CONTRIBUTING.md with zig docs, zig std lib docs, zig clap github, and zig clap generated docs
- Add 1 unit test each for both commands you add
- Update claude.md with links to CONTRIBUTING.md and any other important info worth adding. But be brief and concise
- Create atomic emoji conventional commit but only if all tests pass and build is good

## Code Style & Architecture

### Design Patterns

- Write idiomatic performant zig according to CLAUDE.md
- Keep file structure flat with all cmds just in cmd
- Make commmands easily testable and agnostic to the cli application logic keep all cli specific logic in the main entrypoint

### Code Organization

```
project/
├── build.zig
├── CLAUDE.md
├── CONTRIBUTING.md
├── src/
│   ├── main.zig
│   ├── commands/
```

### Success criteria

All steps completed with pr in production ready state
No hacks or workarounds
