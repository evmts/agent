# Prompt Parser

Rust library for parsing and rendering YAML-based workflow prompts with Jinja2 templating.

## Purpose

Parses `.plue/workflows/*.yaml` files, validates their structure against a JSON schema, and renders prompt templates with runtime context. Provides a C FFI for use from Zig server code.

## Key Files

| File | Description |
|------|-------------|
| `Cargo.toml` | Rust package manifest (staticlib + cdylib) |
| `src/lib.rs` | Parser implementation with FFI exports |

## Dependencies

| Crate | Purpose |
|-------|---------|
| `serde` + `serde_yaml` | YAML deserialization |
| `serde_json` | JSON schema validation |
| `minijinja` | Jinja2 template rendering |
| `jsonschema` | Schema validation |
| `thiserror` | Error type definitions |

## Usage

From Zig:

```zig
const parser = @cImport({
    @cInclude("prompt_parser.h");
});

const yaml_content = "...";
const context = "{ \"repo\": \"owner/name\" }";
const result = parser.parse_and_render(yaml_content, context);
```

## Error Handling

The parser returns detailed error messages for:
- YAML syntax errors (with line numbers)
- Template compilation failures
- Missing required fields
- Schema validation failures
- UTF-8 encoding issues

## Build

```bash
cargo build --release
```

Outputs:
- `libprompt_parser.a` - Static library for Zig linking
- `libprompt_parser.dylib` - Dynamic library for testing
