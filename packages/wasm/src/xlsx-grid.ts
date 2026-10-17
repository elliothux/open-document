import type { CellRange, XlsxCell } from "./xlsx.js";
import type { DrawingBatch, DrawRect } from "./drawing.js";
import { xlsxRect } from "./xlsx-geometry.js";
import { noteCell, noteText } from "./xlsx-sheet.js";
import { record } from "./validation.js";

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
    rect: DrawRect;
    clip: DrawRect;
    range: CellRange;
    diagnostic: string;
  }[];
  notes: { address: string; author: string; text: string; rect: DrawRect }[];
  rows: { index: number; position: number; size: number }[];
  columns: XlsxViewport["rows"];
  diagnostics: string[];
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
