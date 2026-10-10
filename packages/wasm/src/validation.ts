import type { ShapeBatch } from "./foundation.js";

export function record(value: unknown): Record<string, unknown> {
  if (typeof value !== "object" || value === null || Array.isArray(value))
    throw new Error("Invalid Wasm object");
  return value as Record<string, unknown>;
}

export function hasFields(
  value: unknown,
  strings: string[],
  numbers: string[],
): boolean {
  const object = record(value);
  return (
    strings.every((key) => typeof object[key] === "string") &&
    numbers.every(
      (key) => typeof object[key] === "number" && Number.isFinite(object[key]),
    )
  );
}

export function arrayOf(
  value: unknown,
  check: (entry: unknown) => boolean,
): boolean {
  return Array.isArray(value) && value.every(check);
}

export function glyphs(value: unknown): ShapeBatch["glyphs"] {
  if (
    !arrayOf(value, (entry) =>
      hasFields(
        entry,
        ["outline"],
        [
          "id",
          "cluster",
          "font",
          "x",
          "y",
          "scale",
          "advance",
          "yAdvance",
          "xOffset",
          "yOffset",
        ],
      ),
    )
  )
    throw new Error("Invalid glyphs returned by Wasm");
  return value as ShapeBatch["glyphs"];
}
