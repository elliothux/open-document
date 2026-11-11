import { record } from "@open-document/wasm/abi/validation";
import type { XlsxSelectionGeometry } from "./xlsx-geometry.js";

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
