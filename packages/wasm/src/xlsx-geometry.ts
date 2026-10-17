import type { DrawRect } from "./drawing.js";
import { record } from "./validation.js";

export interface XlsxSelectionGeometry extends DrawRect {
  rects: DrawRect[];
}

export function xlsxRect(value: unknown): DrawRect {
  const rect = record(value);
  for (const key of ["x", "y", "width", "height"])
    if (
      typeof rect[key] !== "number" ||
      !Number.isFinite(rect[key]) ||
      ((key === "width" || key === "height") && rect[key] < 0)
    )
      throw new Error("Invalid selection rectangle");
  return value as DrawRect;
}

export function xlsxSelection(value: unknown): XlsxSelectionGeometry {
  xlsxRect(value);
  const selection = record(value);
  if (!Array.isArray(selection.rects) || selection.rects.length > 4)
    throw new Error("Invalid selection regions");
  for (const rect of selection.rects) xlsxRect(rect);
  return value as XlsxSelectionGeometry;
}
