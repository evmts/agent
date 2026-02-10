import { z } from "zod";

export function coerceJson<T>(raw: unknown, schema: z.ZodType<T>): T | null {
  if (raw == null) return null;
  let value = raw;
  if (typeof value === "string") {
    try {
      value = JSON.parse(value);
    } catch {
      return null;
    }
  }
  const result = schema.safeParse(value);
  return result.success ? result.data : null;
}

export function coerceJsonArray<T>(raw: unknown, item: z.ZodType<T>): T[] {
  return coerceJson(raw, z.array(item)) ?? [];
}
