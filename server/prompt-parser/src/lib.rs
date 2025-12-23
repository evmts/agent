use jsonschema::{Draft, JSONSchema};
use minijinja::Environment;
use serde::{Deserialize, Serialize};
use serde_json::Value as JsonValue;
use std::collections::HashMap;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use thiserror::Error;

#[derive(Error, Debug)]
pub enum PromptError {
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("YAML parse error at line {line}: {message}")]
    YamlParse { line: usize, message: String },

    #[error("Template compile error: {0}")]
    TemplateCompile(String),

    #[error("Missing required field: {0}")]
    MissingField(String),

    #[error("Invalid schema: {0}")]
    InvalidSchema(String),

    #[error("UTF-8 error: {0}")]
    Utf8(#[from] std::string::FromUtf8Error),

    #[error("Schema validation failed: {0}")]
    ValidationFailed(String),
}

/// Type definition from frontmatter schema
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(untagged)]
pub enum TypeDef {
    Simple(String),              // "string", "integer", "boolean", etc.
    Optional(Box<TypeDef>),      // "string?"
    Array(Box<TypeDef>),         // "string[]"
    Enum(Vec<String>),           // "a | b | c"
    Object(HashMap<String, TypeDef>), // Nested object
}

impl TypeDef {
    /// Parse type from string (e.g., "string?", "string[]", "a | b | c")
    pub fn from_str(s: &str) -> Self {
        let s = s.trim();

        // Check for optional (ends with ?)
        if s.ends_with('?') {
            let inner = &s[..s.len() - 1];
            return TypeDef::Optional(Box::new(TypeDef::from_str(inner)));
        }

        // Check for array (ends with [])
        if s.ends_with("[]") {
            let inner = &s[..s.len() - 2];
            return TypeDef::Array(Box::new(TypeDef::from_str(inner)));
        }

        // Check for enum (contains |)
        if s.contains('|') {
            let variants: Vec<String> = s.split('|').map(|v| v.trim().to_string()).collect();
            return TypeDef::Enum(variants);
        }

        // Simple type
        TypeDef::Simple(s.to_string())
    }

    /// Convert to JSON Schema representation
    pub fn to_json_schema(&self) -> JsonValue {
        match self {
            TypeDef::Simple(s) => {
                let type_name = match s.as_str() {
                    "string" => "string",
                    "integer" => "integer",
                    "float" | "number" => "number",
                    "boolean" => "boolean",
                    _ => "string", // fallback
                };
                serde_json::json!({ "type": type_name })
            }
            TypeDef::Optional(inner) => {
                serde_json::json!({
                    "anyOf": [inner.to_json_schema(), { "type": "null" }]
                })
            }
            TypeDef::Array(inner) => {
                serde_json::json!({
                    "type": "array",
                    "items": inner.to_json_schema()
                })
            }
            TypeDef::Enum(variants) => {
                serde_json::json!({
                    "type": "string",
                    "enum": variants
                })
            }
            TypeDef::Object(fields) => {
                let properties: HashMap<String, JsonValue> = fields
                    .iter()
                    .map(|(k, v)| (k.clone(), v.to_json_schema()))
                    .collect();

                let required: Vec<String> = fields
                    .iter()
                    .filter(|(_, v)| !matches!(v, TypeDef::Optional(_)))
                    .map(|(k, _)| k.clone())
                    .collect();

                serde_json::json!({
                    "type": "object",
                    "properties": properties,
                    "required": required
                })
            }
        }
    }
}

/// Frontmatter structure
#[derive(Debug, Deserialize)]
struct Frontmatter {
    name: String,
    client: Option<String>,
    #[serde(rename = "type")]
    prompt_type: Option<String>,
    inputs: Option<serde_yaml::Value>,
    output: Option<serde_yaml::Value>,
    tools: Option<Vec<String>>,
    max_turns: Option<u32>,
    extends: Option<String>,
}

/// Parsed prompt definition
#[derive(Debug, Clone, Serialize)]
pub struct PromptDefinition {
    pub name: String,
    pub client: String,
    pub prompt_type: String, // "llm" or "agent"
    pub inputs_schema: JsonValue,
    pub output_schema: JsonValue,
    pub tools: Vec<String>,
    pub max_turns: u32,
    pub body_template: String,
    pub extends: Option<String>,
}

/// Parse a .prompt.md file
pub fn parse_prompt_file(content: &str) -> Result<PromptDefinition, PromptError> {
    // Split frontmatter and body
    let (frontmatter_str, body) = split_frontmatter(content)?;

    // Parse YAML frontmatter
    let frontmatter: Frontmatter = serde_yaml::from_str(&frontmatter_str)
        .map_err(|e| PromptError::YamlParse {
            line: 0,
            message: e.to_string(),
        })?;

    // Validate required fields
    if frontmatter.name.is_empty() {
        return Err(PromptError::MissingField("name".to_string()));
    }

    // Parse schemas
    let inputs_schema = parse_schema(frontmatter.inputs.as_ref())?;
    let output_schema = parse_schema(frontmatter.output.as_ref())?;

    // Create definition
    Ok(PromptDefinition {
        name: frontmatter.name,
        client: frontmatter.client.unwrap_or_else(|| "anthropic/claude-sonnet".to_string()),
        prompt_type: frontmatter.prompt_type.unwrap_or_else(|| "llm".to_string()),
        inputs_schema,
        output_schema,
        tools: frontmatter.tools.unwrap_or_default(),
        max_turns: frontmatter.max_turns.unwrap_or(10),
        body_template: body.to_string(),
        extends: frontmatter.extends,
    })
}

/// Split YAML frontmatter from markdown body
fn split_frontmatter(content: &str) -> Result<(String, String), PromptError> {
    let lines: Vec<&str> = content.lines().collect();

    // Find frontmatter delimiters (---...---)
    if lines.is_empty() || !lines[0].trim().starts_with("---") {
        return Err(PromptError::InvalidSchema(
            "Missing frontmatter delimiter (---) at start of file".to_string(),
        ));
    }

    // Find end of frontmatter
    let end_idx = lines[1..]
        .iter()
        .position(|line| line.trim().starts_with("---"))
        .ok_or_else(|| {
            PromptError::InvalidSchema("Missing closing frontmatter delimiter (---)".to_string())
        })?
        + 1; // +1 because we started searching from index 1

    let frontmatter = lines[1..end_idx].join("\n");
    let body = lines[end_idx + 1..].join("\n");

    Ok((frontmatter, body))
}

/// Parse schema from YAML value into JSON Schema
fn parse_schema(yaml: Option<&serde_yaml::Value>) -> Result<JsonValue, PromptError> {
    match yaml {
        None => Ok(serde_json::json!({})),
        Some(value) => {
            let schema = parse_schema_value(value)?;
            Ok(schema)
        }
    }
}

fn parse_schema_value(value: &serde_yaml::Value) -> Result<JsonValue, PromptError> {
    match value {
        serde_yaml::Value::String(s) => {
            let typedef = TypeDef::from_str(s);
            Ok(typedef.to_json_schema())
        }
        serde_yaml::Value::Mapping(m) => {
            let mut properties = serde_json::Map::new();
            let mut required = Vec::new();

            for (k, v) in m {
                let key = k
                    .as_str()
                    .ok_or_else(|| PromptError::InvalidSchema("Non-string key in schema".to_string()))?;

                let prop_schema = parse_schema_value(v)?;

                // Check if this field is required (not optional)
                if !is_optional_schema(&prop_schema) {
                    required.push(key.to_string());
                }

                properties.insert(key.to_string(), prop_schema);
            }

            Ok(serde_json::json!({
                "type": "object",
                "properties": properties,
                "required": required
            }))
        }
        serde_yaml::Value::Sequence(seq) => {
            // Array with single element defines the item schema
            if seq.len() == 1 {
                let item_schema = parse_schema_value(&seq[0])?;
                Ok(serde_json::json!({
                    "type": "array",
                    "items": item_schema
                }))
            } else {
                Err(PromptError::InvalidSchema(
                    "Array schema must have exactly one element defining the item type".to_string(),
                ))
            }
        }
        _ => Err(PromptError::InvalidSchema(format!(
            "Unsupported YAML type: {:?}",
            value
        ))),
    }
}

fn is_optional_schema(schema: &JsonValue) -> bool {
    // Check if schema has anyOf with null
    if let Some(any_of) = schema.get("anyOf") {
        if let Some(array) = any_of.as_array() {
            return array.iter().any(|v| v.get("type") == Some(&JsonValue::String("null".to_string())));
        }
    }
    false
}

/// Render a template with given inputs
pub fn render_template(template_str: &str, inputs: &HashMap<String, String>) -> Result<String, PromptError> {
    let mut env = Environment::new();
    env.add_template("prompt", template_str)
        .map_err(|e| PromptError::TemplateCompile(e.to_string()))?;

    let template = env.get_template("prompt")
        .map_err(|e| PromptError::TemplateCompile(e.to_string()))?;

    let rendered = template.render(inputs)
        .map_err(|e| PromptError::TemplateCompile(e.to_string()))?;

    Ok(rendered)
}

/// Validate JSON data against a JSON Schema
pub fn validate_json(schema: &JsonValue, data: &JsonValue) -> Result<(), PromptError> {
    let compiled = JSONSchema::options()
        .with_draft(Draft::Draft7)
        .compile(schema)
        .map_err(|e| PromptError::InvalidSchema(e.to_string()))?;

    if let Err(errors) = compiled.validate(data) {
        let error_messages: Vec<String> = errors.map(|e| e.to_string()).collect();
        return Err(PromptError::ValidationFailed(error_messages.join(", ")));
    }

    Ok(())
}

/// Validate that data matches a schema, returning detailed error messages
pub fn validate_with_details(schema: &JsonValue, data: &JsonValue) -> Result<Vec<String>, PromptError> {
    let compiled = JSONSchema::options()
        .with_draft(Draft::Draft7)
        .compile(schema)
        .map_err(|e| PromptError::InvalidSchema(e.to_string()))?;

    let result = compiled.validate(data);

    match result {
        Ok(_) => Ok(Vec::new()), // No errors
        Err(errors) => {
            let error_messages: Vec<String> = errors
                .map(|e| {
                    format!(
                        "path: {}, error: {}",
                        e.instance_path,
                        e
                    )
                })
                .collect();
            Ok(error_messages)
        }
    }
}

// ============================================================================
// FFI Interface for Zig
// ============================================================================

#[repr(C)]
pub struct CPromptDefinition {
    pub name: *mut c_char,
    pub client: *mut c_char,
    pub prompt_type: *mut c_char,
    pub inputs_schema_json: *mut c_char,
    pub output_schema_json: *mut c_char,
    pub body_template: *mut c_char,
    pub max_turns: u32,
}

#[repr(C)]
pub struct CPromptError {
    pub message: *mut c_char,
}

/// Parse a prompt file (FFI)
#[no_mangle]
pub extern "C" fn prompt_parser_parse(
    content: *const c_char,
    out_def: *mut *mut CPromptDefinition,
    out_error: *mut *mut CPromptError,
) -> bool {
    let content_str = unsafe {
        match CStr::from_ptr(content).to_str() {
            Ok(s) => s,
            Err(e) => {
                *out_error = Box::into_raw(Box::new(CPromptError {
                    message: CString::new(format!("UTF-8 error: {}", e))
                        .unwrap()
                        .into_raw(),
                }));
                return false;
            }
        }
    };

    match parse_prompt_file(content_str) {
        Ok(def) => {
            let c_def = CPromptDefinition {
                name: CString::new(def.name).unwrap().into_raw(),
                client: CString::new(def.client).unwrap().into_raw(),
                prompt_type: CString::new(def.prompt_type).unwrap().into_raw(),
                inputs_schema_json: CString::new(def.inputs_schema.to_string())
                    .unwrap()
                    .into_raw(),
                output_schema_json: CString::new(def.output_schema.to_string())
                    .unwrap()
                    .into_raw(),
                body_template: CString::new(def.body_template).unwrap().into_raw(),
                max_turns: def.max_turns,
            };

            unsafe {
                *out_def = Box::into_raw(Box::new(c_def));
            }
            true
        }
        Err(e) => {
            let error = CPromptError {
                message: CString::new(format!("{}", e)).unwrap().into_raw(),
            };
            unsafe {
                *out_error = Box::into_raw(Box::new(error));
            }
            false
        }
    }
}

/// Free a CPromptDefinition
#[no_mangle]
pub extern "C" fn prompt_parser_free_definition(def: *mut CPromptDefinition) {
    if def.is_null() {
        return;
    }

    unsafe {
        let def = Box::from_raw(def);
        if !def.name.is_null() {
            let _ = CString::from_raw(def.name);
        }
        if !def.client.is_null() {
            let _ = CString::from_raw(def.client);
        }
        if !def.prompt_type.is_null() {
            let _ = CString::from_raw(def.prompt_type);
        }
        if !def.inputs_schema_json.is_null() {
            let _ = CString::from_raw(def.inputs_schema_json);
        }
        if !def.output_schema_json.is_null() {
            let _ = CString::from_raw(def.output_schema_json);
        }
        if !def.body_template.is_null() {
            let _ = CString::from_raw(def.body_template);
        }
    }
}

/// Free a CPromptError
#[no_mangle]
pub extern "C" fn prompt_parser_free_error(error: *mut CPromptError) {
    if error.is_null() {
        return;
    }

    unsafe {
        let error = Box::from_raw(error);
        if !error.message.is_null() {
            let _ = CString::from_raw(error.message);
        }
    }
}

/// Validate JSON data against a schema (FFI)
/// Returns true if valid, false if invalid
/// If invalid, out_error_count and out_errors will be populated
#[no_mangle]
pub extern "C" fn prompt_parser_validate_json(
    schema_json: *const c_char,
    data_json: *const c_char,
    out_error_count: *mut usize,
    out_errors: *mut *mut *mut c_char,
    out_error: *mut *mut CPromptError,
) -> bool {
    let schema_str = unsafe {
        match CStr::from_ptr(schema_json).to_str() {
            Ok(s) => s,
            Err(e) => {
                *out_error = Box::into_raw(Box::new(CPromptError {
                    message: CString::new(format!("UTF-8 error in schema: {}", e))
                        .unwrap()
                        .into_raw(),
                }));
                return false;
            }
        }
    };

    let data_str = unsafe {
        match CStr::from_ptr(data_json).to_str() {
            Ok(s) => s,
            Err(e) => {
                *out_error = Box::into_raw(Box::new(CPromptError {
                    message: CString::new(format!("UTF-8 error in data: {}", e))
                        .unwrap()
                        .into_raw(),
                }));
                return false;
            }
        }
    };

    // Parse JSON
    let schema: JsonValue = match serde_json::from_str(schema_str) {
        Ok(v) => v,
        Err(e) => {
            unsafe {
                *out_error = Box::into_raw(Box::new(CPromptError {
                    message: CString::new(format!("Schema JSON parse error: {}", e))
                        .unwrap()
                        .into_raw(),
                }));
            }
            return false;
        }
    };

    let data: JsonValue = match serde_json::from_str(data_str) {
        Ok(v) => v,
        Err(e) => {
            unsafe {
                *out_error = Box::into_raw(Box::new(CPromptError {
                    message: CString::new(format!("Data JSON parse error: {}", e))
                        .unwrap()
                        .into_raw(),
                }));
            }
            return false;
        }
    };

    // Validate
    match validate_with_details(&schema, &data) {
        Ok(errors) => {
            if errors.is_empty() {
                // Valid
                unsafe {
                    *out_error_count = 0;
                    *out_errors = std::ptr::null_mut();
                }
                true
            } else {
                // Invalid - return error messages
                let error_ptrs: Vec<*mut c_char> = errors
                    .into_iter()
                    .map(|msg| CString::new(msg).unwrap().into_raw())
                    .collect();

                unsafe {
                    *out_error_count = error_ptrs.len();
                    let boxed = error_ptrs.into_boxed_slice();
                    *out_errors = Box::into_raw(boxed) as *mut *mut c_char;
                }
                false
            }
        }
        Err(e) => {
            unsafe {
                *out_error = Box::into_raw(Box::new(CPromptError {
                    message: CString::new(format!("Validation error: {}", e))
                        .unwrap()
                        .into_raw(),
                }));
            }
            false
        }
    }
}

/// Free validation error array
#[no_mangle]
pub extern "C" fn prompt_parser_free_validation_errors(
    errors: *mut *mut c_char,
    count: usize,
) {
    if errors.is_null() || count == 0 {
        return;
    }

    unsafe {
        let errors_slice = std::slice::from_raw_parts_mut(errors, count);
        for error_ptr in errors_slice {
            if !error_ptr.is_null() {
                let _ = CString::from_raw(*error_ptr);
            }
        }
        let _ = Box::from_raw(std::slice::from_raw_parts_mut(errors, count));
    }
}

/// Render a Jinja2 template with JSON inputs (FFI)
/// Returns the rendered string, or null on error
#[no_mangle]
pub extern "C" fn prompt_parser_render_template(
    template_str: *const c_char,
    inputs_json: *const c_char,
    out_rendered: *mut *mut c_char,
    out_error: *mut *mut CPromptError,
) -> bool {
    let template = unsafe {
        match CStr::from_ptr(template_str).to_str() {
            Ok(s) => s,
            Err(e) => {
                *out_error = Box::into_raw(Box::new(CPromptError {
                    message: CString::new(format!("UTF-8 error in template: {}", e))
                        .unwrap()
                        .into_raw(),
                }));
                return false;
            }
        }
    };

    let inputs_str = unsafe {
        match CStr::from_ptr(inputs_json).to_str() {
            Ok(s) => s,
            Err(e) => {
                *out_error = Box::into_raw(Box::new(CPromptError {
                    message: CString::new(format!("UTF-8 error in inputs: {}", e))
                        .unwrap()
                        .into_raw(),
                }));
                return false;
            }
        }
    };

    // Parse JSON inputs into a HashMap for minijinja
    let inputs_json_value: JsonValue = match serde_json::from_str(inputs_str) {
        Ok(v) => v,
        Err(e) => {
            unsafe {
                *out_error = Box::into_raw(Box::new(CPromptError {
                    message: CString::new(format!("JSON parse error: {}", e))
                        .unwrap()
                        .into_raw(),
                }));
            }
            return false;
        }
    };

    // Convert JSON object to HashMap for template rendering
    // minijinja can handle JsonValue directly, so we'll use that
    let mut env = Environment::new();
    if let Err(e) = env.add_template("prompt", template) {
        unsafe {
            *out_error = Box::into_raw(Box::new(CPromptError {
                message: CString::new(format!("Template compile error: {}", e))
                    .unwrap()
                    .into_raw(),
            }));
        }
        return false;
    }

    let tmpl = match env.get_template("prompt") {
        Ok(t) => t,
        Err(e) => {
            unsafe {
                *out_error = Box::into_raw(Box::new(CPromptError {
                    message: CString::new(format!("Template get error: {}", e))
                        .unwrap()
                        .into_raw(),
                }));
            }
            return false;
        }
    };

    let rendered = match tmpl.render(&inputs_json_value) {
        Ok(r) => r,
        Err(e) => {
            unsafe {
                *out_error = Box::into_raw(Box::new(CPromptError {
                    message: CString::new(format!("Template render error: {}", e))
                        .unwrap()
                        .into_raw(),
                }));
            }
            return false;
        }
    };

    unsafe {
        *out_rendered = CString::new(rendered).unwrap().into_raw();
    }
    true
}

/// Free a rendered template string
#[no_mangle]
pub extern "C" fn prompt_parser_free_string(s: *mut c_char) {
    if !s.is_null() {
        unsafe {
            let _ = CString::from_raw(s);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_split_frontmatter() {
        let content = r#"---
name: Test
client: anthropic/claude-sonnet
---

This is the body.
"#;

        let (frontmatter, body) = split_frontmatter(content).unwrap();
        assert!(frontmatter.contains("name: Test"));
        assert_eq!(body.trim(), "This is the body.");
    }

    #[test]
    fn test_parse_simple_prompt() {
        let content = r#"---
name: SimplePrompt
client: anthropic/claude-sonnet

inputs:
  query: string

output:
  result: string
---

Answer this: {{ query }}
"#;

        let def = parse_prompt_file(content).unwrap();
        assert_eq!(def.name, "SimplePrompt");
        assert_eq!(def.client, "anthropic/claude-sonnet");
        assert_eq!(def.prompt_type, "llm");
    }

    #[test]
    fn test_typedef_optional() {
        let typedef = TypeDef::from_str("string?");
        match typedef {
            TypeDef::Optional(inner) => {
                assert!(matches!(*inner, TypeDef::Simple(_)));
            }
            _ => panic!("Expected Optional type"),
        }
    }

    #[test]
    fn test_typedef_array() {
        let typedef = TypeDef::from_str("string[]");
        match typedef {
            TypeDef::Array(inner) => {
                assert!(matches!(*inner, TypeDef::Simple(_)));
            }
            _ => panic!("Expected Array type"),
        }
    }

    #[test]
    fn test_typedef_enum() {
        let typedef = TypeDef::from_str("info | warning | error");
        match typedef {
            TypeDef::Enum(variants) => {
                assert_eq!(variants.len(), 3);
                assert_eq!(variants[0], "info");
                assert_eq!(variants[1], "warning");
                assert_eq!(variants[2], "error");
            }
            _ => panic!("Expected Enum type"),
        }
    }

    #[test]
    fn test_render_template() {
        let template = "Hello {{ name }}!";
        let mut inputs = HashMap::new();
        inputs.insert("name".to_string(), "World".to_string());

        let result = render_template(template, &inputs).unwrap();
        assert_eq!(result, "Hello World!");
    }

    #[test]
    fn test_validate_json_valid() {
        let schema = serde_json::json!({
            "type": "object",
            "properties": {
                "name": {"type": "string"},
                "age": {"type": "integer"}
            },
            "required": ["name"]
        });

        let data = serde_json::json!({
            "name": "Alice",
            "age": 30
        });

        assert!(validate_json(&schema, &data).is_ok());
    }

    #[test]
    fn test_validate_json_invalid() {
        let schema = serde_json::json!({
            "type": "object",
            "properties": {
                "name": {"type": "string"},
                "age": {"type": "integer"}
            },
            "required": ["name"]
        });

        let data = serde_json::json!({
            "age": 30
        });

        assert!(validate_json(&schema, &data).is_err());
    }

    #[test]
    fn test_validate_with_details() {
        let schema = serde_json::json!({
            "type": "object",
            "properties": {
                "name": {"type": "string"},
                "age": {"type": "integer"}
            },
            "required": ["name", "age"]
        });

        let data = serde_json::json!({
            "name": "Alice"
        });

        let errors = validate_with_details(&schema, &data).unwrap();
        assert!(!errors.is_empty());
        assert!(errors[0].contains("age"));
    }

    #[test]
    fn test_render_template_ffi() {
        let template = CString::new("Hello {{ name }}! You are {{ age }} years old.").unwrap();
        let inputs = CString::new(r#"{"name": "Alice", "age": 30}"#).unwrap();

        let mut rendered: *mut c_char = std::ptr::null_mut();
        let mut error: *mut CPromptError = std::ptr::null_mut();

        let success = prompt_parser_render_template(
            template.as_ptr(),
            inputs.as_ptr(),
            &mut rendered,
            &mut error,
        );

        assert!(success);
        assert!(!rendered.is_null());
        assert!(error.is_null());

        let rendered_str = unsafe { CStr::from_ptr(rendered).to_str().unwrap() };
        assert_eq!(rendered_str, "Hello Alice! You are 30 years old.");

        prompt_parser_free_string(rendered);
    }
}
