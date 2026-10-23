import type { CellRange, XlsxCell } from "./xlsx.js";
import { xlsxShapeKinds, type XlsxShapeKind } from "./xlsx-shapes.js";
import type { DrawingBatch, DrawRect } from "./drawing.js";
import { xlsxRect } from "./xlsx-geometry.js";
import { noteCell, noteText } from "./xlsx-sheet.js";
import { record, integer, hasFields } from "./validation.js";
import {
  drawingRegions,
  type XlsxDrawingRegion,
} from "./xlsx-drawing-pointer.js";

export interface XlsxViewport extends DrawingBatch {
  id: number;
  revision: number;
  sheet: string;
  scrollX: number;
  scrollY: number;
  extentWidth: number;
  extentHeight: number;
  headerWidth: number;
  headerHeight: number;
  rtl: boolean;
  cells: {
    cell: XlsxCell;
    display: string;
    accessibleText?: string;
    rect: DrawRect;
    clip: DrawRect;
    range: CellRange;
    diagnostic: string;
  }[];
  notes: { address: string; author: string; text: string; rect: DrawRect }[];
  objects: {
    id: string;
    kind: "picture" | "chart" | XlsxShapeKind;
    name: string;
    selected: boolean;
    regions: XlsxDrawingRegion[];
  }[];
  rows: { index: number; position: number; size: number }[];
  columns: XlsxViewport["rows"];
  diagnostics: string[];
}

export function xlsxGridObjects(value: unknown): void {
  if (!Array.isArray(value) || value.length > 256)
    throw new Error("Invalid grid picture list");
  const ids = new Set<string>();
  for (const item of value) {
    const picture = record(item);
    if (
      typeof picture.id !== "string" ||
      !/^[1-9][0-9]*$/.test(picture.id) ||
      ids.has(picture.id) ||
      !(
        picture.kind === "picture" ||
        picture.kind === "chart" ||
        xlsxShapeKinds.some((kind) => kind === picture.kind)
      ) ||
      typeof picture.name !== "string" ||
      picture.name.length > 255 ||
      typeof picture.selected !== "boolean"
    )
      throw new Error("Invalid grid picture identity");
    drawingRegions(picture.regions);
    ids.add(picture.id);
  }
}

export function xlsxGridNotes(value: unknown, bounds: DrawRect): void {
  if (!Array.isArray(value) || value.length > 4096)
    throw new Error("Invalid visible cell notes");
  let units = 0;
  for (const item of value) {
    const note = record(item),
      rect = xlsxRect(note.rect);
    if (
      !noteCell(note.address) ||
      note.address !== note.address.toUpperCase() ||
      !noteText(note.text, 32767) ||
      !noteText(note.author, 255) ||
      rect.width <= 0 ||
      rect.height <= 0 ||
      rect.x < bounds.x ||
      rect.y < bounds.y ||
      rect.x + rect.width > bounds.x + bounds.width + 0.000001 ||
      rect.y + rect.height > bounds.y + bounds.height + 0.000001
    )
      throw new Error("Invalid visible cell note");
    units += note.text.length + note.author.length;
    if (units > 5242880)
      throw new Error("Visible cell notes exceed text budget");
  }
}

export function cellValue(value: unknown): boolean {
  const item = record(value);
  switch (item.kind) {
    case "blank":
      return item.value === null;
    case "text":
    case "error":
      return typeof item.value === "string";
    case "number":
      return typeof item.value === "number" && Number.isFinite(item.value);
    case "boolean":
      return typeof item.value === "boolean";
    default:
      return false;
  }
}

export function xlsxCell(value: unknown): XlsxCell {
  const cell = record(value);
  if (
    !hasFields(
      cell,
      ["address", "input", "display", "readOnlyReason", "calculationReason"],
      [],
    ) ||
    typeof cell.address !== "string" ||
    !/^[A-Z]{1,3}[1-9][0-9]{0,6}$/.test(cell.address) ||
    !integer(cell.row, 1, 1048576) ||
    !integer(cell.column, 1, 16384) ||
    !integer(cell.style, 0, 4095) ||
    !cellValue(cell.value) ||
    !(cell.formula === null || typeof cell.formula === "string") ||
    !(cell.cached === null || cellValue(cell.cached)) ||
    !(cell.calculated === null || cellValue(cell.calculated)) ||
    !["value", "calculated", "imported-cache", "uncalculated"].includes(
      String(cell.calculation),
    )
  )
    throw new Error("Invalid XLSX cell");
  return value as XlsxCell;
}
