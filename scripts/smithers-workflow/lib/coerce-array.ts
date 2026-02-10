/**
 * Coerce an unknown value into an array. Handles:
 * - null/undefined → []
 * - Array → pass-through
 * - JSON string containing an array → parsed
 * - anything else → [] with a console.warn
 */
export function coerceArray<T>(raw: unknown): T[] {
  if (!raw) {
    if (raw !== undefined && raw !== null) {
      console.warn("[smithers-workflow] coerceArray: falsy but non-nullish value:", raw);
    }
    return [];
  }
  if (Array.isArray(raw)) return raw as T[];
  if (typeof raw === "string") {
    try {
      const parsed = JSON.parse(raw);
      if (Array.isArray(parsed)) return parsed as T[];
      console.warn("[smithers-workflow] coerceArray: JSON parsed but not an array:", typeof parsed);
    } catch {
      console.warn("[smithers-workflow] coerceArray: failed to parse string as JSON");
    }
  }
  console.warn("[smithers-workflow] coerceArray: unexpected type, returning []:", typeof raw);
  return [];
}
