# Testing Guide

## Non-Interactive Mode

The agent now supports non-interactive mode where you can pass a prompt directly and get a response without the TUI.

### Usage

```bash
./agent -p "your prompt here"
# or
./agent --prompt "your prompt here"
```

### Examples

```bash
# Test Read tool
./agent -p "Read the file go.mod"

# Test Write tool
./agent -p "Create a new file test.txt with content 'Hello World'"

# Test Edit tool
./agent -p "In main.go, replace 'agent' with 'myagent'"

# Test Glob tool
./agent -p "Find all .go files in the tool directory"

# Test Grep tool
./agent -p "Search for 'func.*Tool' in the tool directory"

# Test List tool
./agent -p "Show me the directory structure of the tool directory"

# Test Bash tool
./agent -p "Run 'go version' to show the Go version"
```

## Test Scripts

Two test scripts are provided:

### 1. Individual Tool Testing

Test one tool at a time:

```bash
./test-individual.sh <tool_name>
```

Available tools:
- `read` - Test Read tool
- `write` - Test Write tool
- `edit` - Test Edit tool
- `glob` - Test Glob tool
- `grep` - Test Grep tool
- `ls` - Test List tool
- `bash` - Test Bash tool
- `multiedit` - Test MultiEdit tool
- `patch` - Test Patch tool
- `webfetch` - Test WebFetch tool
- `todo` - Test Todo tools
- `all` - Run all tests sequentially

Example:
```bash
./test-individual.sh read
./test-individual.sh edit
./test-individual.sh all
```

### 2. Full Test Suite

Run all tests at once:

```bash
./test-tools.sh
```

This creates a test area, runs tests for all tools, and offers to clean up afterward.

## Building

```bash
# Build the agent
go build -o agent .

# Run in interactive mode
./agent -i

# Run with a prompt
./agent -p "your prompt"
```

## Test Environment

The test scripts automatically create a `test_area/` directory with sample files:
- `test.txt` - Simple text file with 3 lines
- `sample.js` - Sample JavaScript code
- `subdir/nested.txt` - Nested file for testing directory operations

## Tool Verification Checklist

- [ ] **Read** - Can read files and show contents
- [ ] **Write** - Can create new files
- [ ] **Edit** - Can modify existing files with find/replace
- [ ] **Glob** - Can find files matching patterns
- [ ] **Grep** - Can search file contents with regex
- [ ] **List** - Can show directory tree structure
- [ ] **Bash** - Can execute shell commands
- [ ] **MultiEdit** - Can apply multiple edits to one file
- [ ] **Patch** - Can apply patch format changes
- [ ] **WebFetch** - Can fetch web content
- [ ] **Todo** - Can manage todo lists

## Troubleshooting

### API Key
Make sure `ANTHROPIC_API_KEY` is set:
```bash
export ANTHROPIC_API_KEY="your-key-here"
```

### Build Issues
```bash
# Clean and rebuild
go clean
go build -o agent .
```

### Test Area
If tests fail due to missing files:
```bash
rm -rf test_area
./test-individual.sh read  # Will recreate test area
```
