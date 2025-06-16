#!/bin/bash

# Test script for Plue MCP server
# This script sends test commands to the MCP server to verify it's working

echo "Testing Plue MCP Server..."

# Function to send JSON-RPC request
send_request() {
    echo "$1"
}

# Initialize
send_request '{
  "jsonrpc": "2.0",
  "method": "initialize",
  "params": {
    "protocolVersion": "2024-11-05",
    "capabilities": {},
    "clientInfo": {
      "name": "test-client",
      "version": "1.0.0"
    }
  },
  "id": 1
}'

# List tools
send_request '{
  "jsonrpc": "2.0",
  "method": "tools/list",
  "id": 2
}'

# Test launching Plue
send_request '{
  "jsonrpc": "2.0",
  "method": "tools/call",
  "params": {
    "name": "plue_launch",
    "arguments": {}
  },
  "id": 3
}'

# Test sending a message
send_request '{
  "jsonrpc": "2.0",
  "method": "tools/call",
  "params": {
    "name": "plue_send_message",
    "arguments": {
      "message": "Hello from MCP test!"
    }
  },
  "id": 4
}'

# Test switching tabs
send_request '{
  "jsonrpc": "2.0",
  "method": "tools/call",
  "params": {
    "name": "plue_switch_tab",
    "arguments": {
      "tab": "terminal"
    }
  },
  "id": 5
}'

# Test terminal command
send_request '{
  "jsonrpc": "2.0",
  "method": "tools/call",
  "params": {
    "name": "plue_terminal_command",
    "arguments": {
      "command": "echo Testing MCP terminal integration"
    }
  },
  "id": 6
}'

echo "Test complete. Check the output above for responses."