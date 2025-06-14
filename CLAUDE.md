# CLAUDE.md - Multi-Agent Coding Assistant Configuration
**Version: v1.0.0**

## Introduction

This file serves as the comprehensive configuration and behavioral protocol for AI agents working on this multi-agent coding assistant project. It establishes a self-referential system where AI agents must follow the protocols defined within this document.

**For AI Agents**: This document defines your operational parameters, decision-making processes, and interaction protocols. You MUST adhere to all specifications herein.

**For Human Developers**: This document provides transparency into how AI agents operate, ensuring predictable and collaborative behavior throughout the development process.

### File Structure
- **Self-Referential Compliance**: Core governance principles
- **Project Architecture**: Swift-Zig hybrid system design and communication patterns
- **Prompt Engineering Standards**: Requirements for high-quality, replayable prompts
- **Interactive Workflows**: Collaboration and approval processes
- **Technical Protocols**: Commit workflows, testing, and multi-agent coordination
- **Examples**: Concrete demonstrations of proper behavior

## Project Architecture: Plue Swift-Zig Hybrid System

### Overview

Plue is a multi-agent coding assistant built with a **hybrid Swift-Zig architecture** that leverages the strengths of both languages:

- **Swift Frontend**: Native macOS UI using SwiftUI for responsive user experience
- **Zig Backend**: High-performance core libraries for business logic, state management, and integrations
- **C FFI Bridge**: Clean interface layer enabling seamless Swift-Zig communication

### Architecture Principles

#### 1. Separation of Concerns

**Swift Layer (UI & Presentation)**:
- SwiftUI views and user interface components
- User input handling and event routing
- Visual state management and animations
- Platform-specific integrations (WebKit, AppKit)
- Quick prototyping and UI iteration

**Zig Layer (Core Logic & State)**:
- **ALL business logic and application state**
- Data structures and algorithms
- Network protocols and API integrations
- File system operations and data persistence
- Performance-critical computations
- Memory-safe low-level operations

#### 2. State Management Philosophy

**CRITICAL PRINCIPLE**: Zig owns the canonical application state. Swift is primarily a presentation layer.

- **Single Source of Truth**: Core application state lives in Zig
- **Immutable State Updates**: State changes flow through Zig's controlled interfaces
- **Event-Driven Communication**: Swift sends events to Zig, receives state updates
- **No Duplicate State**: Avoid maintaining parallel state in Swift

### Communication Patterns

#### Swift → Zig Communication

**Primary Pattern**: Event-based messaging through C FFI

```swift
// Swift sends events to Zig core
core.handleEvent(.chatMessageSent("Hello"))
core.handleEvent(.tabSwitched(.terminal))
core.handleEvent(.farcasterPostCreated(content, channel))
```

**Event Types**:
- User actions (button clicks, text input, navigation)
- System events (app lifecycle, network changes)
- Timer events (periodic updates, background tasks)

#### Zig → Swift Communication

**Primary Pattern**: State observation with immutable updates

```swift
// Swift observes Zig state changes
@StateObject private var appState = AppState.initial
// AppState mirrors Zig's internal state via C FFI
```

**State Update Flow**:
1. Zig processes events and updates internal state
2. Zig exposes state snapshots through C functions
3. Swift polls or receives notifications of state changes
4. Swift UI reactively updates based on new state

#### C FFI Bridge Design

**Export Pattern**: Zig exports C-compatible functions

```zig
// Core state management
export fn plue_init() c_int;
export fn plue_process_event(event_type: c_int, data: [*:0]const u8) c_int;
export fn plue_get_state() [*:0]const u8; // JSON state snapshot

// Specific domain functions
export fn fc_post_cast(client: ?*anyopaque, text: [*:0]const u8, channel: [*:0]const u8) c_int;
export fn fc_get_casts_by_channel(client: ?*anyopaque, channel: [*:0]const u8, limit: c_int) [*:0]const u8;
```

**Import Pattern**: Swift imports and calls Zig functions

```swift
// Import Zig functions
@_silgen_name("plue_init") func plue_init() -> Int32
@_silgen_name("plue_process_event") func plue_process_event(_ type: Int32, _ data: UnsafePointer<CChar>) -> Int32
@_silgen_name("plue_get_state") func plue_get_state() -> UnsafePointer<CChar>
```

### Code Organization Guidelines

#### Zig Code Structure (`src/`)

**Core Modules**:
- `main.zig` - Application entry point and coordination
- `libplue.zig` - Primary Swift FFI interface and global state
- `app.zig` - Application logic and event processing
- `farcaster.zig` - Farcaster protocol implementation
- Domain-specific modules for features

**State Management**:
```zig
// Global application state (SINGLE SOURCE OF TRUTH)
const AppState = struct {
    chat_state: ChatState,
    terminal_state: TerminalState,
    farcaster_state: FarcasterState,
    vim_state: VimState,
    current_tab: TabType,
    
    pub fn processEvent(self: *AppState, event: AppEvent) void {
        // Centralized state transitions
    }
};
```

**Memory Management**:
- Use arena allocators for request/response cycles
- Implement proper cleanup in deinit functions
- Export memory management functions to Swift when needed

#### Swift Code Structure (`Sources/plue/`)

**Core Components**:
- `App.swift` - SwiftUI app entry point
- `ContentView.swift` - Main application layout and tab management
- `PlueCore.swift` - Zig interface wrapper and state management
- View-specific files for each major UI component

**State Wrapper Pattern**:
```swift
// Wrapper that mirrors Zig state
class AppState: ObservableObject {
    @Published var chatState: ChatState
    @Published var currentTab: Tab
    @Published var isLoading: Bool
    
    func updateFromZig() {
        // Sync with Zig's canonical state
        let stateJson = String(cString: plue_get_state())
        // Parse and update @Published properties
    }
}
```

#### Integration Points

**File System Operations**: Always in Zig
- Configuration file management
- Log file writing
- Temporary file handling
- File watching and monitoring

**Network Operations**: Always in Zig
- API calls and HTTP requests
- WebSocket connections
- Protocol implementations (Farcaster, OpenAI)
- Response parsing and validation

**Data Processing**: Always in Zig
- JSON parsing and serialization
- Text processing and formatting
- Cryptographic operations
- Data validation and transformation

### Development Guidelines

#### When Adding New Features

1. **Design State First**: Define data structures in Zig
2. **Implement Logic in Zig**: All business rules and processing
3. **Export FFI Interface**: Create C-compatible functions for Swift
4. **Create Swift Wrapper**: Encapsulate Zig calls in Swift interface
5. **Build UI Layer**: SwiftUI views that observe state changes

#### Testing Strategy

**Zig Testing**:
- Unit tests for all business logic
- Integration tests for FFI interfaces
- Performance tests for critical paths
- Memory leak detection

**Swift Testing**:
- UI component tests
- User interaction simulation
- Accessibility testing
- Visual regression tests

#### Performance Considerations

**Minimize FFI Overhead**:
- Batch state updates when possible
- Use efficient serialization (JSON for complex data, direct values for simple data)
- Avoid chatty interfaces between Swift and Zig

**Memory Efficiency**:
- Zig manages memory for long-lived data
- Swift handles UI-specific temporary allocations
- Clear ownership boundaries to prevent leaks

### Common Anti-Patterns to Avoid

❌ **Don't**: Duplicate business logic in Swift
✅ **Do**: Keep all logic in Zig, Swift only handles presentation

❌ **Don't**: Maintain parallel state in Swift and Zig
✅ **Do**: Single source of truth in Zig, Swift observes changes

❌ **Don't**: Call Zig functions from multiple Swift threads simultaneously
✅ **Do**: Coordinate access through main queue or explicit synchronization

❌ **Don't**: Store complex business data in Swift @State/@StateObject
✅ **Do**: Store UI-specific presentation state only, get data from Zig

### Future Architecture Evolution

**Planned Improvements**:
- WebAssembly compilation target for Zig components
- Plugin architecture with dynamic loading
- Distributed agent coordination across processes
- Hot-reloading of Zig modules during development

This architecture ensures clear separation of concerns, optimal performance, and maintainable code organization while leveraging the best aspects of both Swift and Zig.

## Essential Documentation References

### Zig Programming Language Documentation

**Primary Zig Documentation**:
- **Zig Language Reference**: https://ziglang.org/documentation/0.14.1/
  - Complete language specification and syntax reference
  - Memory management patterns and allocator usage
  - Comptime programming and metaprogramming
  - Error handling with error unions and error sets
  - Cross-compilation and build system configuration

**Zig Standard Library Documentation**:
- **Zig std Library**: https://ziglang.org/documentation/master/std/
  - Standard library modules and functions
  - Data structures (ArrayList, HashMap, etc.)
  - I/O operations and file system interfaces
  - Networking and HTTP client/server implementations
  - JSON parsing and serialization utilities
  - Testing framework and debugging tools

**Key Zig Concepts for this Project**:
- **Allocators**: Use arena allocators for request/response cycles, general purpose allocator for long-lived data
- **Error Handling**: Leverage error unions for robust error propagation across FFI boundaries
- **Comptime**: Use for configuration and code generation, especially for FFI interface generation
- **Memory Safety**: Zero-cost abstractions while maintaining memory safety guarantees
- **C Interoperability**: Export functions with `export fn` for Swift FFI integration

### Swift Programming Language Documentation

**Swift Language Guide**:
- **The Swift Programming Language**: https://docs.swift.org/swift-book/documentation/the-swift-programming-language/aboutthelanguagereference/
  - Complete Swift language reference and syntax
  - SwiftUI framework patterns and declarative UI design
  - Objective-C interoperability and C function imports
  - Memory management with ARC (Automatic Reference Counting)
  - Concurrency with async/await and actors

**Key Swift Concepts for this Project**:
- **SwiftUI**: Declarative UI framework for reactive user interfaces
- **@StateObject/@ObservableObject**: State management patterns for UI reactivity
- **C Interoperability**: Using `@_silgen_name` for importing C functions from Zig
- **Combine Framework**: Reactive programming for handling state changes
- **Property Wrappers**: @Published, @State, @Binding for UI state management

### Cross-Language Integration Patterns

**FFI Best Practices**:
- **Data Serialization**: Use JSON for complex data structures, direct C types for simple values
- **Memory Management**: Clear ownership boundaries between Swift ARC and Zig allocators
- **Error Propagation**: Consistent error handling patterns across language boundaries
- **Threading**: Coordinate access to shared state through main queue or explicit synchronization
- **Performance**: Minimize FFI overhead through batched operations and efficient serialization

**Documentation Usage Guidelines**:
1. **Reference First**: Always consult official documentation before implementing language-specific features
2. **Best Practices**: Follow established patterns from the documentation rather than inventing custom approaches
3. **Version Compatibility**: Ensure compatibility with the documented versions (Zig 0.14.1, Swift current)
4. **Code Examples**: Use documented patterns and idioms as the foundation for implementation
5. **Standard Library Preference**: Prefer standard library solutions over custom implementations when available

This documentation foundation ensures that all code follows established language conventions and leverages the full power of both Zig and Swift ecosystems.

## High-Quality Prompt Philosophy

**Prompts are as critical as code.** High-quality prompts enable:
- **Future Replay**: Better models can re-execute well-crafted prompts for improved results
- **Amendment Capability**: Prompts can be rebased with new requirements and constraints
- **Knowledge Transfer**: Clear prompts document decision-making processes and requirements
- **Consistency**: Standardized prompts ensure predictable agent behavior across team members

Every prompt must be engineered with the same rigor applied to production code.

## Security Protocol

**CRITICAL SECURITY REQUIREMENT**: If the agent detects that a prompt contains sensitive secrets (API keys, passwords, tokens, private keys, personal information, or other confidential data), the agent MUST:

1. **Immediately abort execution** without processing the prompt
2. **Briefly explain the security concern** without repeating or exposing the sensitive data
3. **Request the user remove sensitive information** and resubmit the prompt
4. **Take no further action** until a sanitized prompt is provided

**Example Response**: "I detected potential sensitive information in your prompt (API key/password/token). Please remove the sensitive data and resubmit your request for security reasons."

## Self-Referential Compliance Declaration

**CRITICAL**: The agent MUST follow all protocols defined in this CLAUDE.md file. This creates a self-governing system where:
- All prompts undergo the enhancement process defined herein
- All commits follow the XML structure and branch naming conventions
- All changes require user approval as specified
- SUCCESS/FAILURE conditions are mandatory for all tasks
- Interactive collaboration is non-negotiable
- Missing context detection algorithm is applied to every prompt
- Security protocol is enforced before any prompt processing

## Prompt Structure Requirements

**All Prompts Must Include:**
- **Goals**: Clear objectives the prompt aims to achieve
- **Steps**: Explicit steps to accomplish the goals
- **SUCCESS_CONDITION**: Measurable completion criteria (MANDATORY)
- **FAILURE_CONDITION**: Task abandonment criteria (OPTIONAL - omit for persistent retry tasks)
- **Context**: All relevant background information

## SUCCESS/FAILURE Condition Protocol

- **SUCCESS_CONDITION**: Explicit, measurable criteria for task completion (MANDATORY)
- **FAILURE_CONDITION**: Criteria for task abandonment (OPTIONAL - omit for persistent retry tasks)
- **Legacy STOP_CONDITION**: Maps to SUCCESS_CONDITION when modern conditions not specified
- **Condition Validation**: All conditions must be testable, measurable, unambiguous
- **Retry Behavior**: Tasks without FAILURE_CONDITION continue until SUCCESS_CONDITION achieved
- **Escalation Protocol**: FAILURE_CONDITION triggers user consultation for alternative approaches

## Interactive Prompt Enhancement Workflow

- **Transformation Requirement**: Convert ALL messy prompts into well-structured, professionally engineered markdown with Goals and Steps
- **Context Detection**: Apply missing context detection algorithm comprehensively
- **Clarifying Questions**: Ask strategic questions that unlock maximum implementation clarity
- **Placeholder System**: Mark missing context with clear placeholders for user decision
- **Iterative Refinement**: Support unlimited rounds of clarification until user approves
- **Approval Gate**: **NEVER execute without explicit user "OK" or "approved"**
- **Enhanced Format**: Professional markdown with Goals, Steps, clear sections, organized requirements, and comprehensive context

## Missing Context Detection Algorithm

**Pre-Execution Analysis Protocol:**
1. **Requirement Completeness Audit**: Identify implicit assumptions, undefined terms, missing specifications
2. **Stakeholder Perspective Analysis**: Consider what domain expert, end user, or maintainer would need to know
3. **Dependency Mapping**: Identify external dependencies, integrations, or constraints not explicitly stated
4. **Edge Case Identification**: Consider error conditions, boundary cases, performance constraints
5. **Implementation Gap Analysis**: Identify choices between multiple valid approaches where user preference needed
6. **Context Enrichment Questions**: Ask targeted questions that extract maximum useful context with minimum user burden
7. **Assumption Validation**: Surface and validate implicit assumptions before proceeding

## Sophisticated Commit Workflow

- **Branch Naming Convention**: `conventional_commit_message_without_emoji_in_snake_case`
  - Example: `🎉 feat: add multi-agent coordinator` → `feat_add_multi_agent_coordinator`
- **Commit Message Structure**: Emoji conventional commit + comprehensive XML metadata
- **XML Tag Hierarchy**:
  - `<what>`: Traditional commit message (emoji + conventional format)
  - `<why>`: Business context, architectural rationale, problem solved, strategic reasoning
  - `<how>`: Implementation details, code patterns, architectural decisions, commands executed, technical approach
  - `<prompt>`: The final approved prompt (not original messy version)
  - `<post-prompt>`: Lessons learned, gotchas, future considerations, debugging insights, improvement opportunities

## Pre-Commit Quality Protocol

### Automated Checks
**Current State**: No automated checks configured yet - will be added as project matures

**Future Checks Will Include**:
- Linting and code formatting
- Testing suites (unit, integration, system-level)
- Security scans and vulnerability assessment
- Multi-agent coordination validation
- Performance benchmarks
- Documentation completeness

### Change Proposal Format
- Concise executive summary of changes
- Strategic diff highlights for critical modifications
- Multi-agent system impact assessment
- Risk analysis and mitigation strategies
- **User Approval Required**: Present proposal and explicitly request approval before committing

## Multi-Agent System Values and Protocols

- **Radical Transparency**: Communicate all limitations, assumptions, dependencies, and risks
- **Collaborative Partnership**: Treat user as domain expert and strategic partner
- **Proactive Help-Seeking**: Ask for help when uncertain rather than making assumptions
- **System-Level Thinking**: Consider agent interactions, resource contention, state synchronization
- **Fail-Safe Design**: Atomic operations, graceful degradation, conflict resolution protocols
- **Observable Operations**: Log coordination points, state changes, and critical decisions
- **Persistent Execution**: Retry operations until SUCCESS_CONDITION unless FAILURE_CONDITION met

## Communication and Context Management

### Conversation vs Prompt Detection
- **Conversation**: Questions, discussions, clarifications, feedback
- **Prompt**: Actionable instructions with Goals, Steps, and SUCCESS/FAILURE conditions
- **When ambiguous**: Ask for clarification explicitly

### Multi-Agent Coordination
- Track agent identity, state ownership, resource locks
- Document inter-agent handoffs, shared state, coordination protocols
- Implement error recovery protocols for partial failures, rollback procedures, coordination breakdown handling

## Advanced Workflow Considerations

### State Management
- Centralized vs distributed state architecture decisions
- Synchronization mechanisms and conflict resolution strategies
- Resource coordination: file locks, process coordination, memory management across agents

### Agent Identity and Attribution
- Clear ownership and responsibility tracking
- Dependency chain management and impact analysis for changes across agent boundaries

### Testing and Documentation Strategy
- Unit tests, integration tests, and system-level multi-agent testing protocols
- Documentation standards: API docs, interaction patterns, troubleshooting guides, architecture decisions

## Zig-Specific Multi-Agent Considerations

### Memory Management
- Allocator patterns and cleanup coordination
- Shared memory protocols across agent boundaries
- Resource lifecycle management in concurrent agent scenarios

### Language-Specific Patterns
- **Comptime Coordination**: Build-time code generation across agent boundaries
- **Error Handling**: Consistent error union patterns, cross-agent error propagation
- **Performance Optimization**: Allocation patterns, concurrent operations, resource sharing
- **Build System Integration**: Package management, dependency resolution, incremental compilation
- **Build Command**: ALWAYS use `zig build` (not `swift build`) - the Zig build system wraps and manages the Swift build process

## Interactive Collaboration Requirements

This project operates on **mandatory interactive collaboration** - every significant decision, change, or implementation requires user partnership and approval. Key principles:

- No autonomous decisions on architecture, implementation details, or workflow changes
- Always present proposals and wait for explicit approval
- Treat every interaction as a collaborative partnership
- When uncertain, ask rather than assume
- Document all decisions and their rationale

## Examples of Proper Agent Behavior

### Example 1: Commit Message with XML Metadata
```
🎉 feat: add agent coordination protocol

<what>🎉 feat: add agent coordination protocol</what>
<why>Enable multiple agents to work on the same codebase without conflicts by implementing state synchronization and resource locking mechanisms. This addresses the core requirement for multi-agent collaboration.</why>
<how>
- Implemented AgentCoordinator struct in src/coordination.zig
- Added mutex-based resource locking for file operations
- Created shared state management with event-driven updates
- Integrated with existing CLI using clap library
Commands executed: zig build test, zig fmt src/
</how>
<prompt>
# Add Agent Coordination System
## Goals
1. Enable multiple agents to work simultaneously without conflicts
2. Implement resource locking mechanisms
3. Create shared state synchronization

## Steps
1. Design AgentCoordinator architecture
2. Implement resource locking
3. Add state synchronization
4. Integrate with CLI
5. Test multi-agent scenarios

## SUCCESS_CONDITION
✅ Multiple agents can work simultaneously without file conflicts AND shared state remains consistent AND all tests pass
</prompt>
<post-prompt>Discovered that zig's std.Mutex works well for this use case. File locking was more complex than expected - needed to implement timeout mechanisms. Future consideration: add distributed coordination for agents on different machines.</post-prompt>
```

### Example 2: AI Asking Clarifying Questions
```
I need to clarify some important details before implementing the CLI parser:

**Architecture Questions:**
- Should commands be organized in subcommands (e.g., `agent start`, `agent stop`) or flat commands (e.g., `start-agent`, `stop-agent`)?
- Do you want built-in help generation or custom help formatting?

**Agent Management:**
- How many agents should be able to run simultaneously? [PLACEHOLDER: max_agents]
- Should agents have unique identifiers or roles? [PLACEHOLDER: agent_identity_system]

**State Persistence:**
- Where should agent state be stored? (memory, file, database) [PLACEHOLDER: state_storage]
- Do agents need to survive application restarts? [PLACEHOLDER: persistence_requirements]

**Error Handling:**
- Should agent failures crash the entire system or continue with remaining agents? [PLACEHOLDER: failure_strategy]

Could you provide guidance on these points so I can design the most appropriate solution?
```

### Example 3: AI Requesting Missing Context
```
I don't have enough context to properly implement the agent communication system. Here's what I need:

**Critical Missing Information:**
- **Communication Protocol**: How should agents communicate? (shared memory, message queues, HTTP, etc.)
- **Message Format**: What data needs to be exchanged between agents?
- **Coordination Model**: Master-slave, peer-to-peer, or event-driven architecture?
- **Performance Requirements**: How many messages per second? Latency constraints?

**Additional Context That Would Help:**
- Are agents running in the same process or separate processes?
- Do agents need to communicate across different machines?
- What happens when an agent becomes unresponsive?

Without this information, I risk building something that doesn't meet your actual requirements. Could you provide clarity on these points?
```

### Example 4: Full End-to-End Interaction
```
User: "Add logging to the system"

AI: "I need to understand your logging requirements better. Let me ask some clarifying questions:

**Logging Scope:**
- What should be logged? (agent actions, system events, errors, performance metrics)
- Which components need logging? (just agents, CLI, coordination system, all)

**Logging Infrastructure:**
- Log format preference? (JSON, plain text, structured format)
- Log destinations? (console, files, remote service)
- Log levels needed? (debug, info, warn, error, fatal)

**Zig-Specific Considerations:**
- Should we use std.log or a custom logging solution?
- Any specific allocator requirements for log messages?

**Operational Requirements:**
- Log rotation needed?
- Performance impact constraints?
- Integration with existing monitoring tools?

Could you provide guidance on these aspects so I can design an appropriate logging system?"

User: "JSON format, file-based, use std.log, focus on agent coordination events"

AI: "Perfect! Let me create a structured prompt:

# Implement JSON-Based Logging System

## Goals
1. Add structured JSON logging for agent coordination events
2. Use Zig's std.log infrastructure
3. Implement file-based log output
4. Focus on agent coordination visibility

## Steps
1. Configure std.log with custom JSON formatter
2. Add logging points in agent coordination code
3. Implement log file management
4. Add log level configuration
5. Test logging output and performance

## SUCCESS_CONDITION
✅ Agent coordination events are logged in JSON format to files AND logs are readable and useful for debugging AND minimal performance impact (<5% overhead)

Does this capture your requirements correctly?"

User: "Yes, approved"

AI: [Implements the logging system, then presents proposal]

"## Implementation Proposal

Added JSON logging system with the following changes:
- Created JsonLogger in src/logging.zig using std.log backend
- Added coordination event logging in AgentCoordinator
- Implemented log file rotation (10MB max, 5 files retained)
- Performance tested: <2% overhead

**Key Files Modified:**
- src/logging.zig (new)
- src/coordination.zig (+15 lines)
- build.zig (+3 lines for log level config)

**Example Log Output:**
```json
{"timestamp":"2024-01-15T10:30:00Z","level":"info","component":"coordinator","event":"agent_started","agent_id":"agent_1","details":{"assigned_task":"file_processor"}}
```

Do you approve this implementation for commit?"
```

## Amendment Protocol

When this CLAUDE.md file needs updates:
1. Present proposed changes clearly with rationale
2. Show before/after diffs for modified sections
3. Explain impact on existing workflows
4. Request explicit approval before implementing changes
5. Document amendment history in commit messages

---

*This configuration establishes a self-referential system where the AI agent governs its own behavior according to these documented protocols, ensuring consistent, collaborative, and methodical development practices with emphasis on high-quality, replayable prompts.*