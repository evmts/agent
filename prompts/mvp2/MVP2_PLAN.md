# MVP2 Plan: Plue with OpenCode Integration

## Overview

This document outlines the MVP2 implementation plan for Plue, which leverages the existing OpenCode implementation instead of reimplementing its functionality. This approach dramatically simplifies the architecture while maintaining all desired features.

## Architecture Comparison

### Original MVP Architecture
```
Swift UI → Zig Core → TypeScript/Bun Executables → AI Providers/Tools
```

### MVP2 Architecture
```
Swift UI → Zig Core → HTTP → OpenCode Server
```

## Benefits of MVP2 Approach

1. **No Reimplementation**: Leverage OpenCode's existing AI provider integrations, tool system, and session management
2. **Proven Functionality**: OpenCode is already battle-tested and actively maintained
3. **Faster Development**: Focus only on the integration layer instead of reimplementing complex features
4. **Maintainability**: Updates to OpenCode automatically benefit Plue
5. **Simpler Testing**: Test against the actual OpenCode implementation
6. **Reduced Complexity**: Eliminate the TypeScript/Bun executable layer entirely

## Implementation Strategy

The MVP2 implementation follows a bottom-up approach, building the foundation first and then layering features on top:

### Phase 1: Infrastructure (Prompts 01-03)
- OpenCode server lifecycle management
- HTTP client infrastructure
- Basic API client implementation

### Phase 2: Core Features (Prompts 04-07)
- Session management bridge
- Message system bridge
- Provider management bridge
- Tool system bridge

### Phase 3: Integration (Prompts 08-10)
- Configuration merging
- State synchronization
- Complete FFI implementation

## Prompt Progression

1. **OpenCode Server Management**: Spawn and manage OpenCode as a subprocess
2. **HTTP Client Infrastructure**: Build robust HTTP communication layer
3. **OpenCode API Client**: Create type-safe client for OpenCode's HTTP API
4. **Session Bridge**: Map Plue's session API to OpenCode
5. **Message Bridge**: Handle messages and streaming responses
6. **Provider Bridge**: Use OpenCode's AI provider management
7. **Tool Bridge**: Leverage OpenCode's tool system
8. **Configuration Integration**: Merge Plue and OpenCode settings
9. **State Synchronization**: Keep Zig and OpenCode state in sync
10. **FFI Integration**: Implement the complete PLUE_CORE_API.md interface

## Key Design Decisions

### State Management
- Zig maintains a cache of OpenCode state for performance
- State synchronization happens through polling and webhooks
- All mutations go through OpenCode to maintain consistency

### Error Handling
- Translate OpenCode HTTP errors to Plue error codes
- Provide detailed error context for debugging
- Handle network failures gracefully with retries

### Performance Optimization
- Connection pooling for HTTP requests
- Efficient state diffing to minimize updates
- Streaming responses for real-time feedback

### Configuration
- Plue configuration takes precedence
- OpenCode configuration used as defaults
- Environment variables supported by both systems

## Development Workflow

Each prompt follows the same structured approach:
1. Clear context about the current state
2. Explicit task requirements
3. Implementation steps with examples
4. Success criteria
5. Git workflow instructions

## Success Metrics

The MVP2 will be considered successful when:
- All PLUE_CORE_API.md functions are implemented
- OpenCode server lifecycle is properly managed
- State remains synchronized between systems
- Performance meets or exceeds the original MVP design
- All tests pass with >95% coverage

## Future Enhancements

After MVP2 completion, potential enhancements include:
- WebSocket support for real-time updates
- Multiple OpenCode server support
- Plugin system using OpenCode's MCP
- Direct database integration for state persistence