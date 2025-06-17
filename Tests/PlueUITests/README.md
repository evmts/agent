# Plue UI Tests

This directory contains UI tests for the Plue application using XCUITest framework.

## Setup Complete ✅

The UI testing infrastructure has been fully set up with:

### 1. Instrumented UI Elements
All key UI components have been tagged with accessibility identifiers:
- **Tab buttons**: All 8 tabs (Prompt, Farcaster, Agent, Terminal, Web, Editor, Diff, Worktree)
- **Chat UI**: Input field, send button, welcome message
- **Farcaster**: Channel rows with dynamic identifiers
- **Agent**: Welcome title

### 2. Test Files Created
- `PlueUITests.swift` - Core test suite with 3 fundamental tests
- `PlueUITestsExtended.swift` - Extended test suite with comprehensive coverage
- `PlueUITestsLaunchTests.swift` - Launch and screenshot tests
- `PlueUITestHelpers.swift` - Helper extensions for readable tests
- `AccessibilityIdentifiers+UITests.swift` - Test copy of identifiers

### 3. Test Coverage
- ✅ App launch and initial state verification
- ✅ Tab navigation between all views
- ✅ Chat message sending and interaction
- ✅ Multiple message handling
- ✅ Farcaster channel navigation
- ✅ Agent view state verification
- ✅ Theme toggle testing
- ✅ Keyboard shortcuts testing

## Running UI Tests

Since Plue uses a hybrid Zig/Swift build system, UI tests need to be run through Xcode:

1. Build the Zig libraries:
   ```bash
   zig build
   ```

2. Open the project in Xcode:
   ```bash
   open Package.swift
   ```

3. In Xcode:
   - Wait for package resolution to complete
   - Select the "plue" scheme
   - Choose Product > Test (⌘U) or
   - Run individual UI tests by clicking the diamond icon next to test methods

## Helper Script

Use the provided script for setup instructions:
```bash
./run-ui-tests.sh
```

## Accessibility Identifiers

All key UI elements have been instrumented with accessibility identifiers defined in:
- `Sources/plue/AccessibilityIdentifiers.swift` (main app)
- `Tests/PlueUITests/AccessibilityIdentifiers+UITests.swift` (test copy)

These identifiers ensure stable and maintainable UI tests that won't break with UI layout changes.