import { WasmSession, encodeBytes } from "./session.js";
import { DocumentError, type Budget } from "./foundation.js";
import { record, hasFields, arrayOf } from "./validation.js";
import { drawingBatch, type DrawingBatch, type DrawRect } from "./drawing.js";
import {
  checkXlsxCellFormat,
  xlsxFormatting,
  copiedCellFormat,
  type CopiedCellFormat,
  type XlsxCellFormat,
  type XlsxFormatting,
} from "./xlsx-format.js";
export {
  checkXlsxCellFormat,
  xlsxNumberFormats,
  copiedCellFormat,
} from "./xlsx-format.js";
export type {
  XlsxCellFormat,
  XlsxFormatting,
  XlsxCellBorder,
  CopiedCellFormat,
} from "./xlsx-format.js";

export interface GridViewport {
  sheet: string;
  scrollX: number;
  scrollY: number;
  width: number;
  height: number;
  profile: Record<string, string>;
  reveal?: boolean;
}

export interface XlsxViewport extends DrawingBatch {
  id: number;
  revision: number;
  sheet: string;
  scrollX: number;
  scrollY: number;
  extentWidth: number;
  extentHeight: number;
  cells: {
    cell: XlsxCell;
    display: string;
    rect: DrawRect;
    clip: DrawRect;
    range: CellRange;
    diagnostic: string;
  }[];
  rows: { index: number; position: number; size: number }[];
  columns: XlsxViewport["rows"];
  diagnostics: string[];
}

export interface XlsxSelectionGeometry extends DrawRect {
  rects: DrawRect[];
}

export interface PrintOptions {
  width: number;
  height: number;
  top: number;
  right: number;
  bottom: number;
  left: number;
  range?: string;
}

export interface XlsxPrintLayout extends DrawingBatch {
  id: number;
  revision: number;
  sheet: string;
}

export type CellValue =
  | { kind: "blank"; value: null }
  | { kind: "text" | "error"; value: string }
  | { kind: "number"; value: number }
  | { kind: "boolean"; value: boolean };

export interface CellRange {
  top: number;
  left: number;
  bottom: number;
  right: number;
}

export interface XlsxCell {
  address: string;
  row: number;
  column: number;
  style: number;
  value: CellValue;
  input: string;
  formula: string | null;
  cached: CellValue | null;
  calculated: CellValue | null;
  calculation: "value" | "calculated" | "imported-cache" | "uncalculated";
  display: string;
  readOnlyReason: string;
}

export interface XlsxQuery {
  revision: number;
  mainPart: string;
  fontKeys: string[];
  normalFont: string;
  merging: {
    range: string;
    merged: boolean;
    discarded: number;
    mergeReason: string;
    unmergeReason: string;
  };
  sheets: {
    id: string;
    name: string;
    state: "visible" | "hidden" | "veryHidden";
    protected: boolean;
  }[];
  sheet: string;
  cells: XlsxCell[];
  selection: { sheet: string; range: CellRange };
  canUndo: boolean;
  canRedo: boolean;
  historyBytes: number;
  readOnlyReason: string;
  sheetEditReason: string;
  sheetRenameReason: string;
  dimensions: {
    rowHeight: number | null;
    columnWidth: number | null;
    readOnlyReason: string;
  };
  frozen: { rows: number; columns: number; readOnlyReason: string };
  formatting: XlsxFormatting;
  diagnostics: string[];
  date1904: boolean;
}

export type XlsxClearMode = "contents" | "formats" | "all";

export type XlsxSheetEdit =
  | { action: "freeze"; rows: number; columns: number }
  | { action: "merge"; range: string; discard: boolean }
  | { action: "unmerge"; range: string }
  | { action: "add" }
  | { action: "copy" }
  | { action: "delete" }
  | { action: "move"; index: number }
  | { action: "rename"; name: string }
  | {
      action: "rowHeight" | "columnWidth";
      first: number;
      last: number;
      size: number;
    }
  | { action: "visibility"; state: "visible" | "hidden" | "veryHidden" };

export function checkXlsxSheetEdit(value: unknown): void {
  const change = record(value);
  if (
    change.action === "freeze" &&
    integer(change.rows, 0, 1048575) &&
    integer(change.columns, 0, 16383)
  )
    return;
  if (
    (change.action === "merge" || change.action === "unmerge") &&
    typeof change.range === "string" &&
    change.range.length > 0 &&
    change.range.length <= 64 &&
    (change.action === "unmerge" || typeof change.discard === "boolean")
  )
    return;
  if (
    change.action === "add" ||
    change.action === "copy" ||
    change.action === "delete"
  )
    return;
  if (
    (change.action === "rowHeight" || change.action === "columnWidth") &&
    integer(change.first, 1, change.action === "rowHeight" ? 1048576 : 16384) &&
    integer(
      change.last,
      Number(change.first),
      change.action === "rowHeight" ? 1048576 : 16384,
    ) &&
    typeof change.size === "number" &&
    Number.isFinite(change.size) &&
    change.size >= 0 &&
    change.size <= (change.action === "rowHeight" ? 409.5 : 255)
  )
    return;
  if (
    change.action === "rename" &&
    typeof change.name === "string" &&
    change.name.length > 0 &&
    change.name.length <= 31 &&
    change.name.isWellFormed() &&
    !change.name.startsWith("'") &&
    !change.name.endsWith("'") &&
    !Array.from(change.name).some(
      (character) =>
        character.charCodeAt(0) < 32 || "[]:*?/\\".includes(character),
    ) &&
    !change.name.includes("\ufffe") &&
    !change.name.includes("\uffff")
  )
    return;
  if (change.action === "move" && integer(change.index, 0, 255)) return;
  if (
    change.action === "visibility" &&
    ["visible", "hidden", "veryHidden"].includes(String(change.state))
  )
    return;
  throw new Error("Invalid worksheet edit");
}

function integer(value: unknown, min: number, max: number): boolean {
  return (
    typeof value === "number" &&
    Number.isInteger(value) &&
    value >= min &&
    value <= max
  );
}

function cellValue(value: unknown): boolean {
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

export function xlsxQuery(value: unknown): XlsxQuery {
  const query = record(value);
  const merging = record(query.merging);
  if (
    !hasFields(merging, ["range", "mergeReason", "unmergeReason"], []) ||
    typeof merging.range !== "string" ||
    merging.range.length === 0 ||
    merging.range.length > 64 ||
    typeof merging.merged !== "boolean" ||
    !integer(merging.discarded, 0, 100000)
  )
    throw new Error("Invalid cell merging state");
  xlsxFormatting(query.formatting);
  const dimensions = record(query.dimensions);
  const frozen = record(query.frozen);
  if (
    !integer(frozen.rows, 0, 1048575) ||
    !integer(frozen.columns, 0, 16383) ||
    typeof frozen.readOnlyReason !== "string"
  )
    throw new Error("Invalid frozen panes");
  if (
    typeof dimensions.readOnlyReason !== "string" ||
    !["rowHeight", "columnWidth"].every((key) => {
      const size = dimensions[key];
      return (
        size === null ||
        (typeof size === "number" &&
          Number.isFinite(size) &&
          size >= 0 &&
          size <= (key === "rowHeight" ? 409.5 : 255))
      );
    })
  )
    throw new Error("Invalid worksheet dimensions");
  if (
    typeof query.sheetEditReason !== "string" ||
    typeof query.sheetRenameReason !== "string"
  )
    throw new Error("Invalid worksheet edit reason");
  if (
    !hasFields(
      query,
      ["mainPart", "sheet", "readOnlyReason", "normalFont"],
      [],
    ) ||
    typeof query.normalFont !== "string" ||
    query.normalFont.length === 0 ||
    query.normalFont.length > 270 ||
    !integer(query.revision, 0, 2147483647) ||
    !integer(query.historyBytes, 0, 4194304) ||
    typeof query.canUndo !== "boolean" ||
    typeof query.canRedo !== "boolean" ||
    typeof query.date1904 !== "boolean" ||
    !arrayOf(query.diagnostics, (value) => typeof value === "string") ||
    !Array.isArray(query.fontKeys) ||
    query.fontKeys.length > 4096 ||
    !arrayOf(
      query.fontKeys,
      (value) =>
        typeof value === "string" && value.length > 0 && value.length <= 256,
    ) ||
    !Array.isArray(query.sheets) ||
    query.sheets.length === 0 ||
    query.sheets.length > 256
  )
    throw new Error("Invalid XLSX state returned by Wasm");
  const sheets = new Set<string>();
  for (const value of query.sheets) {
    const sheet = record(value);
    if (
      !hasFields(sheet, ["id", "name"], []) ||
      typeof sheet.id !== "string" ||
      sheets.has(sheet.id) ||
      !sheet.id ||
      !["visible", "hidden", "veryHidden"].includes(String(sheet.state)) ||
      typeof sheet.protected !== "boolean"
    )
      throw new Error("Invalid XLSX worksheet");
    sheets.add(sheet.id);
  }
  const selection = record(query.selection);
  const range = record(selection.range);
  if (
    typeof query.sheet !== "string" ||
    !sheets.has(query.sheet) ||
    typeof selection.sheet !== "string" ||
    !sheets.has(selection.sheet) ||
    !integer(range.top, 1, 1048576) ||
    !integer(range.bottom, Number(range.top), 1048576) ||
    !integer(range.left, 1, 16384) ||
    !integer(range.right, Number(range.left), 16384) ||
    !Array.isArray(query.cells) ||
    query.cells.length > 4096
  )
    throw new Error("Invalid XLSX query range");
  const addresses = new Set<string>();
  for (const value of query.cells) {
    const cell = xlsxCell(value);
    if (addresses.has(cell.address)) throw new Error("Duplicate XLSX cell");
    addresses.add(cell.address);
  }
  return value as XlsxQuery;
}

function xlsxCell(value: unknown): XlsxCell {
  const cell = record(value);
  if (
    !hasFields(cell, ["address", "input", "display", "readOnlyReason"], []) ||
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

function xlsxRect(value: unknown): DrawRect {
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

export function xlsxViewport(value: unknown): XlsxViewport {
  const layout = xlsxPrintLayout(value);
  const grid = record(value);
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
      clip.x < 36 ||
      clip.y < 18 ||
      clip.x + clip.width > layout.regions[0]!.width + 0.000001 ||
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

/** One workbook owner; values, XML transactions and history stay in MoonBit. */
export class XlsxSession extends WasmSession {
  autoFit(
    revision: number,
    sheet: string,
    first: number,
    last: number,
    axis: "rows" | "columns",
    profile: Record<string, string>,
  ): XlsxQuery {
    return xlsxQuery(
      this.call({
        operation: "autoFitXlsx",
        revision,
        sheet,
        first,
        last,
        axis,
        profile,
      }),
    );
  }
  captureFormat(revision: number): CopiedCellFormat {
    return copiedCellFormat(
      this.call({ operation: "captureXlsxFormat", revision }),
    );
  }
  applyFormat(revision: number, format: CopiedCellFormat): XlsxQuery {
    copiedCellFormat(format);
    return xlsxQuery(
      this.call({ operation: "applyXlsxFormat", revision, format }),
    );
  }
  formatCells(revision: number, patch: XlsxCellFormat): XlsxQuery {
    checkXlsxCellFormat(patch);
    return xlsxQuery(
      this.call({ operation: "formatXlsxCells", revision, patch }),
    );
  }
  editSheet(revision: number, sheet: string, change: XlsxSheetEdit): XlsxQuery {
    checkXlsxSheetEdit(change);
    return xlsxQuery(
      this.call({ operation: "editXlsxSheet", revision, sheet, change }),
    );
  }
  create(budget: Budget): XlsxQuery {
    return xlsxQuery(this.call({ operation: "createXlsx", budget }));
  }
  open(bytes: Uint8Array, budget: Budget): XlsxQuery {
    if (bytes.length > budget.fileBytes || bytes.length > budget.retainedBytes)
      throw new DocumentError(
        "limit-exceeded",
        "Byte input exceeds budget",
        "",
        -1,
      );
    return xlsxQuery(
      this.call({ operation: "openXlsx", bytes: encodeBytes(bytes), budget }),
    );
  }
  query(sheet?: string, range?: string): XlsxQuery {
    return xlsxQuery(this.call({ operation: "queryXlsx", sheet, range }));
  }
  select(revision: number, sheet: string, range: string): XlsxQuery {
    return xlsxQuery(
      this.call({ operation: "selectXlsx", revision, sheet, range }),
    );
  }
  replace(
    revision: number,
    sheet: string,
    range: string,
    values: string[][],
    literal = false,
  ): XlsxQuery {
    return xlsxQuery(
      this.call({
        operation: "replaceXlsx",
        revision,
        sheet,
        range,
        values,
        literal,
      }),
    );
  }
  undo(revision: number): XlsxQuery {
    return xlsxQuery(this.call({ operation: "undoXlsx", revision }));
  }
  redo(revision: number): XlsxQuery {
    return xlsxQuery(this.call({ operation: "redoXlsx", revision }));
  }
  save(): Uint8Array {
    return this.bytes({ operation: "saveXlsx" });
  }
  viewport(options: GridViewport): XlsxViewport {
    return xlsxViewport(
      this.call({
        operation: "viewportXlsx",
        ...options,
        reveal: options.reveal ?? false,
      }),
    );
  }
  hit(layoutId: number, x: number, y: number): string {
    const result = record(this.call({ operation: "hitXlsx", layoutId, x, y }));
    if (
      typeof result.address !== "string" ||
      !/^[A-Z]{1,3}[1-9][0-9]{0,6}$/.test(result.address)
    )
      throw new Error("Invalid grid hit");
    return result.address;
  }
  selectionGeometry(layoutId: number): XlsxSelectionGeometry {
    return xlsxSelection(this.call({ operation: "selectionXlsx", layoutId }));
  }
  navigate(
    revision: number,
    direction: "left" | "right" | "up" | "down" | "home",
    extend = false,
  ): XlsxQuery {
    return xlsxQuery(
      this.call({ operation: "navigateXlsx", revision, direction, extend }),
    );
  }
  copy(revision: number): string {
    const result = record(this.call({ operation: "copyXlsx", revision }));
    if (typeof result.text !== "string" || result.text.length > 1048576)
      throw new Error("Invalid clipboard text");
    return result.text;
  }
  paste(revision: number, text: string): XlsxQuery {
    return xlsxQuery(this.call({ operation: "pasteXlsx", revision, text }));
  }
  clear(revision: number, mode: XlsxClearMode = "contents"): XlsxQuery {
    return xlsxQuery(this.call({ operation: "clearXlsx", revision, mode }));
  }
  printLayout(
    revision: number,
    sheet: string,
    options: PrintOptions,
    profile: Record<string, string>,
  ): XlsxPrintLayout {
    return xlsxPrintLayout(
      this.call({
        operation: "printXlsx",
        revision,
        sheet,
        ...options,
        profile,
      }),
    );
  }
  exportPdf(layoutId: number, outputBytes: number): Uint8Array {
    return this.bytes({ operation: "exportXlsxPdf", layoutId, outputBytes });
  }
}
