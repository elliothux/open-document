import type { CellRange, XlsxCell } from "./xlsx.js";
import { xlsxShapeKinds, type XlsxShapeKind } from "./xlsx-shapes.js";
import {
  drawingBatch,
  type DrawingBatch,
  type DrawRect,
} from "@open-document/wasm/abi/drawing";
import { xlsxRect } from "./xlsx-geometry.js";
import { noteCell, noteText } from "./xlsx-sheet.js";
import {
  record,
  integer,
  hasFields,
  arrayOf,
} from "@open-document/wasm/abi/validation";
import { checkSlicerView, type XlsxSlicerView } from "./xlsx-slicer-view.js";
import { checkTimelineView, type XlsxTimelineView } from "./xlsx-timeline.js";
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
    kind: "picture" | "chart" | "slicer" | "timeline" | XlsxShapeKind;
    name: string;
    selected: boolean;
    regions: XlsxDrawingRegion[];
    slicer?: XlsxSlicerView;
    timeline?: XlsxTimelineView;
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
        picture.kind === "slicer" ||
        picture.kind === "timeline" ||
        xlsxShapeKinds.some((kind) => kind === picture.kind)
      ) ||
      typeof picture.name !== "string" ||
      picture.name.length > 255 ||
      typeof picture.selected !== "boolean"
    )
      throw new Error("Invalid grid picture identity");
    drawingRegions(picture.regions);
    if (picture.kind === "slicer") checkSlicerView(picture.slicer);
    else if (picture.slicer !== undefined)
      throw new Error("Unexpected slicer view");
    if (picture.kind === "timeline") checkTimelineView(picture.timeline);
    else if (picture.timeline !== undefined)
      throw new Error("Unexpected timeline view");
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

export interface XlsxPrintLayout extends DrawingBatch {
  id: number;
  revision: number;
  sheet: string;
}

export function xlsxPrintLayout(value: unknown): XlsxPrintLayout {
  drawingBatch(value);
  const layout = record(value);
  if (
    !integer(layout.id, 1, 2147483647) ||
    !integer(layout.revision, 0, 2147483647) ||
    typeof layout.sheet !== "string"
  )
    throw new Error("Invalid XLSX layout identity");
  return value as XlsxPrintLayout;
}

export function xlsxViewport(value: unknown): XlsxViewport {
  const layout = xlsxPrintLayout(value);
  const grid = record(value);
  if (typeof grid.rtl !== "boolean") throw new Error("Invalid grid direction");
  if (!(
    (grid.headerWidth === 36 && grid.headerHeight === 18) ||
    (grid.headerWidth === 0 && grid.headerHeight === 0)
  ))
    throw new Error("Invalid grid header size");
  for (const name of ["scrollX", "scrollY", "extentWidth", "extentHeight"])
    if (
      typeof grid[name] !== "number" ||
      !Number.isFinite(grid[name]) ||
      grid[name] < 0
    )
      throw new Error("Invalid grid extent");
  if (
    layout.regions.length !== 1 ||
    !Array.isArray(grid.cells) ||
    grid.cells.length > 4096 ||
    !arrayOf(grid.diagnostics, (item) => typeof item === "string")
  )
    throw new Error("Invalid grid viewport");
  xlsxGridNotes(grid.notes, {
    x: grid.rtl ? 0 : Number(grid.headerWidth),
    y: Number(grid.headerHeight),
    width: layout.regions[0]!.width - Number(grid.headerWidth),
    height: layout.regions[0]!.height - Number(grid.headerHeight),
  });
  xlsxGridObjects(grid.objects);
  const addresses = new Set<string>();
  for (const value of grid.cells) {
    const item = record(value),
      cell = xlsxCell(item.cell),
      rect = record(item.rect),
      clip = xlsxRect(item.clip),
      range = record(item.range);
    if (
      addresses.has(cell.address) ||
      typeof item.display !== "string" ||
      (item.accessibleText !== undefined &&
        typeof item.accessibleText !== "string") ||
      typeof item.diagnostic !== "string" ||
      !integer(range.top, 1, 1048576) ||
      !integer(range.bottom, Number(range.top), 1048576) ||
      !integer(range.left, 1, 16384) ||
      !integer(range.right, Number(range.left), 16384)
    )
      throw new Error("Invalid visible cell");
    for (const key of ["x", "y", "width", "height"])
      if (
        typeof rect[key] !== "number" ||
        !Number.isFinite(rect[key]) ||
        ((key === "width" || key === "height") && rect[key] < 0)
      )
        throw new Error("Invalid visible cell rectangle");
    addresses.add(cell.address);
    if (
      clip.x < (grid.rtl ? 0 : Number(grid.headerWidth)) ||
      clip.y < Number(grid.headerHeight) ||
      clip.x + clip.width >
        layout.regions[0]!.width -
          (grid.rtl ? Number(grid.headerWidth) : 0) +
          0.000001 ||
      clip.y + clip.height > layout.regions[0]!.height + 0.000001
    )
      throw new Error("Invalid visible cell clip");
  }
  for (const [key, max] of [
    ["rows", 1048576],
    ["columns", 16384],
  ] as const) {
    const axis = grid[key];
    if (!Array.isArray(axis) || axis.length > 4096)
      throw new Error("Invalid grid axis");
    let previous = 0;
    for (const value of axis) {
      const item = record(value);
      if (
        !integer(item.index, previous + 1, max) ||
        typeof item.position !== "number" ||
        !Number.isFinite(item.position) ||
        typeof item.size !== "number" ||
        !Number.isFinite(item.size) ||
        item.size <= 0
      )
        throw new Error("Invalid grid axis item");
      previous = Number(item.index);
    }
  }
  return value as XlsxViewport;
}
