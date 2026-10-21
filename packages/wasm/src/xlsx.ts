import type { XlsxQuery } from "./xlsx-query.js";
import {
  checkXlsxPivotSettings,
  xlsxPivotPreview,
  xlsxPivots,
  type XlsxPivotSettings,
} from "./xlsx-pivot.js";
export * from "./xlsx-pivot.js";
export type { XlsxQuery } from "./xlsx-query.js";
import { xlsxProtection } from "./xlsx-protection.js";
import { protectionSalt } from "./protection-password.js";
export type { XlsxProtection } from "./xlsx-protection.js";
import {
  copiedCells,
  checkXlsxPasteMode,
  type CopiedCells,
  type XlsxPasteMode,
} from "./xlsx-clipboard.js";
export * from "./xlsx-clipboard.js";
import {
  checkXlsxSheetEdit,
  type XlsxSheetEdit,
  xlsxHyperlink,
  xlsxNote,
} from "./xlsx-sheet.js";
export {
  checkXlsxHyperlinkTarget,
  xlsxHyperlink,
  type XlsxHyperlink,
  type XlsxNote,
  xlsxNote,
} from "./xlsx-sheet.js";
import {
  xlsxRect,
  xlsxSelection,
  type XlsxSelectionGeometry,
} from "./xlsx-geometry.js";
export { xlsxSelection, type XlsxSelectionGeometry } from "./xlsx-geometry.js";
import {
  checkXlsxFillTarget,
  xlsxFillPreview,
  type XlsxFillTarget,
  type XlsxFillPreview,
} from "./xlsx-fill.js";
export {
  checkXlsxFillTarget,
  xlsxFillPreview,
  type XlsxFillTarget,
  type XlsxFillPreview,
} from "./xlsx-fill.js";
import { xlsxNames } from "./xlsx-names.js";
export type { XlsxName, XlsxNames, XlsxNameEdit } from "./xlsx-names.js";
import { xlsxStatistics } from "./xlsx-statistics.js";
import { xlsxTables, xlsxTableStyles } from "./xlsx-tables.js";
export * from "./xlsx-tables.js";
import { xlsxOutline } from "./xlsx-outline.js";
export * from "./xlsx-outline.js";
export { xlsxStatistics, type XlsxStatistics } from "./xlsx-statistics.js";
export type { XlsxSortSettings, XlsxSortKey } from "./xlsx-sort.js";
import {
  checkXlsxDuplicateSettings,
  xlsxDuplicates,
  type XlsxDuplicateSettings,
  type XlsxDuplicates,
} from "./xlsx-duplicates.js";
export * from "./xlsx-duplicates.js";
import {
  xlsxDelimitedOptions,
  checkXlsxTextColumnSettings,
  xlsxTextColumns,
  type XlsxDelimitedOptions,
  type XlsxTextColumnSettings,
  type XlsxTextColumns,
} from "./xlsx-delimited.js";
export * from "./xlsx-delimited.js";
import { xlsxFilterState, spreadsheetDate } from "./xlsx-filter.js";
export { xlsxRelativeDatePeriods, spreadsheetDate } from "./xlsx-filter.js";
export type {
  XlsxFilterValues,
  XlsxFilterColumn,
  XlsxFilterCondition,
  XlsxFilterOperator,
  XlsxCustomFilter,
  XlsxRankFilter,
  XlsxAverageFilter,
  XlsxDateFilter,
  XlsxCalendarFilter,
  XlsxRelativeDateFilter,
  XlsxColorFilter,
  XlsxFilterSettings,
  XlsxFilterState,
} from "./xlsx-filter.js";
import { xlsxConditionalState } from "./xlsx-conditional.js";
export {
  checkXlsxConditionalFormat,
  conditionalThresholds,
} from "./xlsx-conditional.js";
export type {
  XlsxConditionalFormat,
  XlsxConditionalRule,
  XlsxConditionalState,
  XlsxConditionalStop,
  XlsxConditionalThreshold,
  XlsxDataBar,
} from "./xlsx-conditional.js";
import { xlsxValidationState } from "./xlsx-validation.js";
import { xlsxSparklines } from "./xlsx-sparkline.js";
export type {
  XlsxSparkline,
  XlsxSparklineKind,
  XlsxSparklineEdit,
  XlsxSparklines,
} from "./xlsx-sparkline.js";
export {
  checkXlsxDataValidation,
  validationKinds,
  validationOperators,
} from "./xlsx-validation.js";
export type {
  XlsxDataValidation,
  XlsxValidationState,
} from "./xlsx-validation.js";
export { checkXlsxSheetEdit, type XlsxSheetEdit } from "./xlsx-sheet.js";
import { WasmSession, encodeBytes } from "./session.js";
import { DocumentError, type Budget } from "./foundation.js";
import {
  xlsxFindOptions,
  xlsxSearchResult,
  type XlsxFindOptions,
  type XlsxSearchResult,
} from "./xlsx-search.js";
export { xlsxFindOptions, xlsxSearchResult } from "./xlsx-search.js";
export type { XlsxFindOptions, XlsxSearchResult } from "./xlsx-search.js";
import { record, hasFields, arrayOf, integer } from "./validation.js";
import {
  checkPrintOptions,
  xlsxPrintSetup,
  type PrintOptions,
  xlsxPrintRange,
  xlsxHeaderFooter,
} from "./xlsx-print.js";
export { checkXlsxPrintSetup, checkPrintOptions } from "./xlsx-print.js";
export type {
  PrintOptions,
  XlsxPrintSetup,
  XlsxPrintRange,
  XlsxHeaderFooter,
} from "./xlsx-print.js";
import { drawingBatch, type DrawingBatch } from "./drawing.js";
import { xlsxGridNotes, type XlsxViewport } from "./xlsx-grid.js";
import { xlsxCell } from "./xlsx-grid.js";
export type { XlsxViewport } from "./xlsx-grid.js";
import {
  checkXlsxCellFormat,
  xlsxFormatting,
  copiedCellFormat,
  type CopiedCellFormat,
  type XlsxCellFormat,
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

/** CSV/TSV fields stay literal unless a conversion is explicitly enabled. */
export interface GridViewport {
  sheet: string;
  scrollX: number;
  scrollY: number;
  width: number;
  height: number;
  profile: Record<string, string>;
  reveal?: boolean;
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
  calculationReason: string;
  display: string;
  readOnlyReason: string;
}

export type XlsxClearMode = "contents" | "formats" | "all";

export function xlsxQuery(value: unknown): XlsxQuery {
  const query = record(value);
  xlsxProtection(query.protection);
  xlsxProtection(query.workbookProtection);
  xlsxTables(query.tables);
  xlsxTableStyles(query.tableStyles);
  xlsxOutline(query.outline);
  xlsxStatistics(query.statistics);
  xlsxHyperlink(query.hyperlink);
  xlsxNote(query.note);
  xlsxFilterState(query.filter);
  xlsxConditionalState(query.conditionalFormats);
  xlsxValidationState(query.dataValidation);
  xlsxSparklines(query.sparklines);
  xlsxPrintSetup(query.printSetup);
  xlsxPrintRange(query.printRange);
  xlsxHeaderFooter(query.headerFooter);
  const merging = record(query.merging);
  if (
    !hasFields(merging, ["range", "mergeReason", "unmergeReason"], []) ||
    typeof merging.range !== "string" ||
    merging.range.length === 0 ||
    merging.range.length > 64 ||
    typeof merging.merged !== "boolean" ||
    !integer(merging.discarded, 0, 100000) ||
    !integer(merging.discardedNotes, 0, 4095)
  )
    throw new Error("Invalid cell merging state");
  xlsxFormatting(query.formatting);
  const names = xlsxNames(query.names);
  const dimensions = record(query.dimensions);
  const frozen = record(query.frozen);
  const view = record(query.view);
  if (
    typeof view.gridLines !== "boolean" ||
    typeof view.headings !== "boolean" ||
    typeof view.rtl !== "boolean" ||
    typeof view.formulas !== "boolean" ||
    typeof view.readOnlyReason !== "string"
  )
    throw new Error("Invalid worksheet view");
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
  if (
    names.entries.some((item) => item.scope !== null && !sheets.has(item.scope))
  )
    throw new Error("Invalid defined name scope");
  const range = record(selection.range);
  if (
    typeof query.sheet !== "string" ||
    !sheets.has(query.sheet) ||
    typeof selection.sheet !== "string" ||
    !sheets.has(selection.sheet) ||
    typeof selection.address !== "string" ||
    !/^[A-Z]{1,3}[1-9][0-9]{0,6}(:[A-Z]{1,3}[1-9][0-9]{0,6})?$/.test(
      selection.address,
    ) ||
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

/** One workbook owner; values, XML transactions and history stay in MoonBit. */
export class XlsxSession extends WasmSession {
  pivots(revision: number, sheet: string) {
    return xlsxPivots(this.call({ operation: "pivotsXlsx", revision, sheet }));
  }
  pivotPreview(revision: number, settings: XlsxPivotSettings) {
    checkXlsxPivotSettings(settings);
    return xlsxPivotPreview(
      this.call({ operation: "pivotPreviewXlsx", revision, settings }),
    );
  }
  find(
    revision: number,
    sheet: string,
    text: string,
    options: XlsxFindOptions = {},
  ): XlsxSearchResult {
    return xlsxSearchResult(
      this.call({
        operation: "findXlsx",
        revision,
        sheet,
        text,
        options: xlsxFindOptions(options),
      }),
    );
  }
  replaceMatches(
    revision: number,
    sheet: string,
    text: string,
    options: XlsxFindOptions,
    replacement: string,
    index?: number,
  ): XlsxQuery {
    if (
      index !== undefined &&
      (!Number.isInteger(index) || index < 0 || index >= 4096)
    )
      throw new DocumentError(
        "invalid-operation",
        "Invalid search result index",
        "",
        -1,
      );
    return xlsxQuery(
      this.call({
        operation: "replaceXlsxMatches",
        revision,
        sheet,
        text,
        options: xlsxFindOptions(options),
        replacement,
        index,
      }),
    );
  }
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
  editSheet(
    revision: number,
    sheet: string,
    change: XlsxSheetEdit,
    date?: string,
  ): XlsxQuery {
    checkXlsxSheetEdit(change);
    return xlsxQuery(
      this.call({
        operation: "editXlsxSheet",
        revision,
        sheet,
        change,
        date: spreadsheetDate(date),
        passwordSalt:
          change.action === "protection" ||
          change.action === "workbookProtection"
            ? protectionSalt(change.enabled, change.password ?? "")
            : "",
      }),
    );
  }
  duplicates(
    revision: number,
    sheet: string,
    settings: XlsxDuplicateSettings,
  ): XlsxDuplicates {
    checkXlsxDuplicateSettings(settings);
    return xlsxDuplicates(
      this.call({ operation: "duplicatesXlsx", revision, sheet, settings }),
    );
  }
  textColumns(
    revision: number,
    sheet: string,
    settings: XlsxTextColumnSettings,
  ): XlsxTextColumns {
    checkXlsxTextColumnSettings(settings);
    return xlsxTextColumns(
      this.call({ operation: "textColumnsXlsx", revision, sheet, settings }),
    );
  }
  create(budget: Budget, date?: string): XlsxQuery {
    return xlsxQuery(
      this.call({
        operation: "createXlsx",
        budget,
        date: spreadsheetDate(date),
      }),
    );
  }
  importDelimited(
    bytes: Uint8Array,
    delimiter: "," | "\t",
    budget: Budget,
    options: XlsxDelimitedOptions = {},
    date?: string,
  ): XlsxQuery {
    if (delimiter !== "," && delimiter !== "\t")
      throw new Error("Invalid delimiter");
    if (
      bytes.length > Math.min(budget.fileBytes, budget.retainedBytes, 4194304)
    )
      throw new Error("Delimited input exceeds budget");
    return xlsxQuery(
      this.call({
        operation: "importXlsxDelimited",
        bytes: encodeBytes(bytes),
        delimiter,
        budget,
        options: xlsxDelimitedOptions(options),
        date: spreadsheetDate(date),
      }),
    );
  }
  exportCsv(revision: number, selection = false): Uint8Array {
    if (typeof selection !== "boolean") throw new Error("Invalid CSV scope");
    return this.bytes({ operation: "exportXlsxCsv", revision, selection });
  }
  open(bytes: Uint8Array, budget: Budget, date?: string): XlsxQuery {
    if (bytes.length > budget.fileBytes || bytes.length > budget.retainedBytes)
      throw new DocumentError(
        "limit-exceeded",
        "Byte input exceeds budget",
        "",
        -1,
      );
    return xlsxQuery(
      this.call({
        operation: "openXlsx",
        bytes: encodeBytes(bytes),
        budget,
        date: spreadsheetDate(date),
      }),
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
    acceptWarnings = false,
  ): XlsxQuery {
    if (typeof acceptWarnings !== "boolean")
      throw new Error("Invalid validation warning acceptance");
    return xlsxQuery(
      this.call({
        operation: "replaceXlsx",
        revision,
        sheet,
        range,
        values,
        literal,
        acceptWarnings,
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
  fillPreview(layoutId: number, target: XlsxFillTarget): XlsxFillPreview {
    checkXlsxFillTarget(target);
    return xlsxFillPreview(
      this.call({ operation: "fillPreviewXlsx", layoutId, target }),
    );
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
  captureCells(revision: number): CopiedCells {
    return copiedCells(this.call({ operation: "captureXlsxCells", revision }));
  }
  pasteCells(
    revision: number,
    copied: CopiedCells,
    mode: XlsxPasteMode = "all",
    transpose = false,
    acceptWarnings = false,
  ): XlsxQuery {
    copiedCells(copied);
    checkXlsxPasteMode(mode);
    if (typeof transpose !== "boolean" || typeof acceptWarnings !== "boolean")
      throw new Error("Invalid cell paste options");
    return xlsxQuery(
      this.call({
        operation: "pasteXlsxCells",
        revision,
        copied,
        mode,
        transpose,
        acceptWarnings,
      }),
    );
  }
  paste(revision: number, text: string, acceptWarnings = false): XlsxQuery {
    if (typeof acceptWarnings !== "boolean")
      throw new Error("Invalid validation warning acceptance");
    return xlsxQuery(
      this.call({ operation: "pasteXlsx", revision, text, acceptWarnings }),
    );
  }
  clear(revision: number, mode: XlsxClearMode = "contents"): XlsxQuery {
    return xlsxQuery(this.call({ operation: "clearXlsx", revision, mode }));
  }
  printLayout(
    revision: number,
    sheet: string,
    options: PrintOptions | null,
    profile: Record<string, string>,
  ): XlsxPrintLayout {
    checkPrintOptions(options);
    return xlsxPrintLayout(
      this.call({
        operation: "printXlsx",
        revision,
        sheet,
        options,
        profile,
      }),
    );
  }
  exportPdf(layoutId: number, outputBytes: number): Uint8Array {
    return this.bytes({ operation: "exportXlsxPdf", layoutId, outputBytes });
  }
}
