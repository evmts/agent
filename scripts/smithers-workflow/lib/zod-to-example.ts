import type { z } from "zod";

/**
 * Generates a JSON example string from a Zod schema.
 * Used to dynamically pass the expected output format to MDX prompts
 * instead of hardcoding JSON structures.
 */
export function zodSchemaToJsonExample(schema: z.ZodObject<any>): string {
  const shape = schema.shape;
  const example: Record<string, any> = {};

  for (const [key, field] of Object.entries(shape)) {
    example[key] = zodFieldToExample(field as z.ZodTypeAny);
  }

  return JSON.stringify(example, null, 2);
}

function zodFieldToExample(field: z.ZodTypeAny): any {
  const def = (field as any)._def;
  const description = def?.description ?? "";
  const typeName = def?.typeName;

  switch (typeName) {
    case "ZodString":
      return description || "string";
    case "ZodNumber":
      return 0;
    case "ZodBoolean":
      return false;
    case "ZodArray": {
      const inner = zodFieldToExample(def.type);
      return [inner];
    }
    case "ZodEnum":
      return def.values?.[0] ?? "enum";
    case "ZodObject": {
      const obj: Record<string, any> = {};
      for (const [k, v] of Object.entries((field as z.ZodObject<any>).shape)) {
        obj[k] = zodFieldToExample(v as z.ZodTypeAny);
      }
      return obj;
    }
    case "ZodNullable":
      return zodFieldToExample(def.innerType);
    case "ZodOptional":
      return zodFieldToExample(def.innerType);
    default:
      return description || "value";
  }
}
