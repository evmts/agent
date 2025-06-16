# FFI Implementation Plan

## Current State
- Swift frontend uses MockPlueCore which simulates all business logic in Swift
- Zig backend has minimal implementation (just echo function and terminal support)
- The architecture intends for Zig to own all business logic and state

## Required Steps

### 1. Design State Management in Zig
- Create AppState struct in Zig matching the Swift AppState
- Implement state serialization (JSON or MessagePack)
- Design event system for state updates

### 2. Implement Core Business Logic in Zig
- Move reducer logic from MockPlueCore to Zig
- Implement all event handlers
- Handle async operations (API calls, etc.)

### 3. Create FFI Interface
- Define C-compatible functions for:
  - State queries: `plue_get_state() -> *const u8` (JSON)
  - Event handling: `plue_handle_event(event_type: c_int, event_data: *const u8)`
  - Subscriptions: `plue_subscribe(callback: fn(*const u8))`
- Implement proper memory management with free functions

### 4. Update Swift Side
- Create LivePlueCore that calls Zig functions
- Implement JSON/MessagePack serialization
- Handle memory management correctly
- Add proper error handling

### 5. Migration Strategy
- Start with simple state (theme, tab switching)
- Gradually move complex features (chat, terminal, etc.)
- Keep MockPlueCore as fallback during development

## Challenges
- Async operations across FFI boundary
- Complex state serialization
- Memory management between Swift ARC and Zig allocators
- Error propagation across languages

## Benefits
- True separation of concerns
- Potential for WASM compilation
- Better testability
- Consistent business logic across platforms