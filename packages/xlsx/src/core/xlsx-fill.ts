import { record } from "@open-document/wasm/abi/validation";
import { xlsxSelection, type XlsxSelectionGeometry } from "./xlsx-geometry.js";

export type XlsxFillTarget =
  | { kind: "adjacent"; ctrl?: boolean }
  | { kind: "point"; x: number; y: number; ctrl?: boolean }
  | {
      kind: "direction";
      direction: "up" | "down" | "left" | "right";
      ctrl?: boolean;
    };

export interface XlsxFillPreview {
  source: string;
  range: string;
  direction: "up" | "down" | "left" | "right";
  mode: "auto" | "copy" | "linear" | "shrink";
  geometry: XlsxSelectionGeometry;
  end: XlsxSelectionGeometry;
}

export function checkXlsxFillTarget(value: unknown): void {
  const target = record(value);
  const fields =
    target.kind === "point"
      ? ["kind", "x", "y", "ctrl"]
      : target.kind === "adjacent"
        ? ["kind", "ctrl"]
        : ["kind", "direction", "ctrl"];
  if (
    ("ctrl" in target && typeof target.ctrl !== "boolean") ||
    Object.keys(target).some((key) => !fields.includes(key)) ||
    (target.kind === "point"
      ? typeof target.x !== "number" ||
        !Number.isFinite(target.x) ||
        typeof target.y !== "number" ||
        !Number.isFinite(target.y)
      : target.kind === "adjacent"
        ? false
        : target.kind !== "direction" ||
          typeof target.direction !== "string" ||
          !["up", "down", "left", "right"].includes(String(target.direction)))
  )
    throw new Error("Invalid fill target");
}

export function xlsxFillPreview(value: unknown): XlsxFillPreview {
  const result = record(value);
  for (const key of ["source", "range"]) {
    if (
      typeof result[key] !== "string" ||
      !/^[A-Z]{1,3}[1-9][0-9]{0,6}(:[A-Z]{1,3}[1-9][0-9]{0,6})?$/.test(
        result[key],
      )
    )
      throw new Error("Invalid fill range");
  }
  if (
    !["auto", "copy", "linear", "shrink"].includes(String(result.mode)) ||
    typeof result.mode !== "string" ||
    (result.mode === "shrink" &&
      !["up", "left"].includes(String(result.direction))) ||
    typeof result.direction !== "string" ||
    !["up", "down", "left", "right"].includes(result.direction)
  )
    throw new Error("Invalid fill direction");
  xlsxSelection(result.geometry);
  xlsxSelection(result.end);
  return value as XlsxFillPreview;
}
