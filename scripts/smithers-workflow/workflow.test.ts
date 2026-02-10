import { describe, it, expect } from "bun:test";
import { coerceArray } from "./lib/coerce-array";

describe("coerceArray", () => {
  it("returns [] for null", () => {
    expect(coerceArray(null)).toEqual([]);
  });

  it("returns [] for undefined", () => {
    expect(coerceArray(undefined)).toEqual([]);
  });

  it("returns [] for empty string", () => {
    expect(coerceArray("")).toEqual([]);
  });

  it("returns [] for false", () => {
    expect(coerceArray(false)).toEqual([]);
  });

  it("returns [] for 0", () => {
    expect(coerceArray(0)).toEqual([]);
  });

  it("passes through an array directly", () => {
    const arr = [1, 2, 3];
    expect(coerceArray(arr)).toBe(arr);
  });

  it("passes through an empty array", () => {
    const arr: unknown[] = [];
    expect(coerceArray(arr)).toBe(arr);
  });

  it("parses a JSON string containing an array", () => {
    const result = coerceArray('[{"id":"T-001"},{"id":"T-002"}]');
    expect(result).toEqual([{ id: "T-001" }, { id: "T-002" }]);
  });

  it("returns [] for a JSON string that is not an array", () => {
    expect(coerceArray('{"id":"T-001"}')).toEqual([]);
  });

  it("returns [] for malformed JSON string", () => {
    expect(coerceArray("{not valid json")).toEqual([]);
  });

  it("returns [] for a non-JSON string", () => {
    expect(coerceArray("hello")).toEqual([]);
  });

  it("returns [] for a number", () => {
    expect(coerceArray(42)).toEqual([]);
  });

  it("returns [] for an object (non-array)", () => {
    expect(coerceArray({ foo: "bar" })).toEqual([]);
  });

  it("preserves type parameter for arrays", () => {
    type Item = { id: string };
    const arr: Item[] = [{ id: "a" }];
    const result = coerceArray<Item>(arr);
    expect(result[0].id).toBe("a");
  });
});
