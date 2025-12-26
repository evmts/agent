/**
 * Frontmatter Parser
 *
 * Parse and serialize YAML frontmatter in markdown files.
 * Focused implementation for git-based issue tracking.
 */

export interface ParsedDocument<T = Record<string, unknown>> {
  data: T;
  content: string;
}

/**
 * Parse a markdown file with YAML frontmatter
 */
export function parseFrontmatter<T = Record<string, unknown>>(
  source: string
): ParsedDocument<T> {
  const frontmatterRegex = /^---\r?\n([\s\S]*?)\r?\n---\r?\n?([\s\S]*)$/;
  const match = source.match(frontmatterRegex);

  if (!match) {
    return { data: {} as T, content: source.trim() };
  }

  const [, yamlStr, content] = match;
  const data = parseYaml(yamlStr) as T;

  return { data, content: content.trim() };
}

/**
 * Serialize data and content back to frontmatter format
 */
export function stringifyFrontmatter<T extends Record<string, unknown>>(
  data: T,
  content: string
): string {
  const yaml = serializeYaml(data);
  return `---\n${yaml}---\n\n${content}`;
}

/**
 * Simple YAML parser for known issue/comment structures
 */
function parseYaml(yaml: string): Record<string, unknown> {
  const result: Record<string, unknown> = {};
  const lines = yaml.split("\n");

  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    if (line.trim() === "") {
      i++;
      continue;
    }

    const colonIndex = line.indexOf(":");
    if (colonIndex === -1) {
      i++;
      continue;
    }

    const key = line.substring(0, colonIndex).trim();
    const valueStr = line.substring(colonIndex + 1).trim();

    // Check for nested object (author:)
    if (valueStr === "") {
      const nested: Record<string, unknown> = {};
      i++;
      while (i < lines.length && lines[i].startsWith("  ")) {
        const nestedLine = lines[i].substring(2); // Remove leading spaces
        const nestedColonIndex = nestedLine.indexOf(":");
        if (nestedColonIndex > 0) {
          const nestedKey = nestedLine.substring(0, nestedColonIndex).trim();
          const nestedValue = nestedLine.substring(nestedColonIndex + 1).trim();
          nested[nestedKey] = parseValue(nestedValue);
        }
        i++;
      }
      result[key] = nested;
      continue;
    }

    // Check for inline array [item1, item2]
    if (valueStr.startsWith("[") && valueStr.endsWith("]")) {
      const inner = valueStr.slice(1, -1).trim();
      if (inner === "") {
        result[key] = [];
      } else {
        result[key] = inner.split(",").map((item) => parseValue(item.trim()));
      }
      i++;
      continue;
    }

    // Check for multi-line array
    if (valueStr === "" || valueStr === "|" || valueStr === ">") {
      // Look ahead for array items
      const nextLine = lines[i + 1];
      if (nextLine?.trim().startsWith("- ")) {
        const items: unknown[] = [];
        i++;
        while (i < lines.length && lines[i].trim().startsWith("- ")) {
          const itemValue = lines[i].trim().substring(2).trim();
          items.push(parseValue(itemValue));
          i++;
        }
        result[key] = items;
        continue;
      }
    }

    result[key] = parseValue(valueStr);
    i++;
  }

  return result;
}

/**
 * Parse a single YAML value
 */
function parseValue(value: string): unknown {
  if (value === "null" || value === "~") return null;
  if (value === "true") return true;
  if (value === "false") return false;

  // Integer
  if (/^-?\d+$/.test(value)) return parseInt(value, 10);

  // Float
  if (/^-?\d+\.\d+$/.test(value)) return parseFloat(value);

  // Quoted string
  if (
    (value.startsWith('"') && value.endsWith('"')) ||
    (value.startsWith("'") && value.endsWith("'"))
  ) {
    return value.slice(1, -1);
  }

  return value;
}

/**
 * Serialize an object to YAML
 */
function serializeYaml(
  obj: Record<string, unknown>,
  indent: number = 0
): string {
  const spaces = "  ".repeat(indent);
  const lines: string[] = [];

  for (const [key, value] of Object.entries(obj)) {
    if (value === null) {
      lines.push(`${spaces}${key}: null`);
    } else if (typeof value === "boolean") {
      lines.push(`${spaces}${key}: ${value}`);
    } else if (typeof value === "number") {
      lines.push(`${spaces}${key}: ${value}`);
    } else if (typeof value === "string") {
      const escaped = escapeYamlString(value);
      lines.push(`${spaces}${key}: ${escaped}`);
    } else if (Array.isArray(value)) {
      if (value.length === 0) {
        lines.push(`${spaces}${key}: []`);
      } else if (value.every((v) => typeof v !== "object")) {
        // Inline array for simple values
        const items = value.map((v) =>
          typeof v === "string" ? escapeYamlString(v) : String(v)
        );
        lines.push(`${spaces}${key}: [${items.join(", ")}]`);
      } else {
        // Multi-line array
        lines.push(`${spaces}${key}:`);
        for (const item of value) {
          if (typeof item === "object" && item !== null) {
            lines.push(
              `${spaces}  - ${serializeYaml(item as Record<string, unknown>, indent + 2).trim()}`
            );
          } else {
            lines.push(`${spaces}  - ${item}`);
          }
        }
      }
    } else if (typeof value === "object") {
      lines.push(`${spaces}${key}:`);
      lines.push(serializeYaml(value as Record<string, unknown>, indent + 1));
    }
  }

  return lines.join("\n") + "\n";
}

/**
 * Escape a string for YAML if needed
 */
function escapeYamlString(str: string): string {
  // Quote strings that contain special characters
  if (
    str.includes(":") ||
    str.includes("#") ||
    str.includes("\n") ||
    str.includes('"') ||
    str.includes("'") ||
    str.startsWith(" ") ||
    str.endsWith(" ") ||
    str === ""
  ) {
    return `"${str.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
  }
  return str;
}
