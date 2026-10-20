import type { DrawRect } from "./drawing.js";
import { record } from "./validation.js";

export function xlsxBounds(
  value: unknown,
  maxCells = 4096,
): {
  top: number;
  bottom: number;
  left: number;
  right: number;
} {
  if (typeof value !== "string") throw new Error("Invalid XLSX range");
  const match =
    /^([A-Z]{1,3})([1-9]\d{0,6})(?::([A-Z]{1,3})([1-9]\d{0,6}))?$/u.exec(value);
  if (!match || match[0] !== value) throw new Error("Invalid XLSX range");
  const column = (text: string) =>
    Array.from(text).reduce((n, c) => n * 26 + c.charCodeAt(0) - 64, 0);
  const result = {
    top: Number(match[2]),
    bottom: Number(match[4] ?? match[2]),
    left: column(match[1]!),
    right: column(match[3] ?? match[1]!),
  };
  if (
    result.top > result.bottom ||
    result.bottom > 1048576 ||
    result.left > result.right ||
    result.right > 16384 ||
    (result.bottom - result.top + 1) * (result.right - result.left + 1) >
      maxCells
  )
    throw new Error("XLSX range exceeds bounds");
  return result;
}

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
