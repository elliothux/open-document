import { record, hasFields, integer, arrayOf } from "./validation.js";
import { xlsxProtection } from "./xlsx-protection.js";
import { xlsxTables, xlsxTableStyles } from "./xlsx-tables.js";
import { xlsxOutline } from "./xlsx-outline.js";
import { xlsxStatistics } from "./xlsx-statistics.js";
import { xlsxHyperlink, xlsxNote } from "./xlsx-sheet.js";
import { xlsxNames } from "./xlsx-names.js";
import { xlsxFilterState } from "./xlsx-filter.js";
import { xlsxConditionalState } from "./xlsx-conditional.js";
import { xlsxValidationState } from "./xlsx-validation.js";
import { xlsxSparklines } from "./xlsx-sparkline.js";
import {
  xlsxPrintSetup,
  xlsxPrintRange,
  xlsxHeaderFooter,
} from "./xlsx-print.js";
import { xlsxFormatting } from "./xlsx-format.js";
import { xlsxCell } from "./xlsx-grid.js";
import type { XlsxTable, XlsxTableStyleChoice } from "./xlsx-tables.js";
import type { XlsxOutline } from "./xlsx-outline.js";
import type { XlsxHyperlink, XlsxNote } from "./xlsx-sheet.js";
import type { XlsxNames } from "./xlsx-names.js";
import type { XlsxStatistics } from "./xlsx-statistics.js";
import type { XlsxFilterState } from "./xlsx-filter.js";
import type { XlsxConditionalState } from "./xlsx-conditional.js";
import type { XlsxValidationState } from "./xlsx-validation.js";
import type { XlsxSparklines } from "./xlsx-sparkline.js";
import type {
  XlsxPrintSetup,
  XlsxPrintRange,
  XlsxHeaderFooter,
} from "./xlsx-print.js";
import type { XlsxFormatting } from "./xlsx-format.js";
import type { CellRange, XlsxCell } from "./xlsx.js";
import type { XlsxProtection } from "./xlsx-protection.js";

export interface XlsxQuery {
  sparklines: XlsxSparklines;
  protection: XlsxProtection;
  workbookProtection: XlsxProtection;
  tables: XlsxTable[];
  tableStyles: XlsxTableStyleChoice[];
  outline: XlsxOutline;
  hyperlink: XlsxHyperlink;
  note: XlsxNote;
  names: XlsxNames;
  statistics: XlsxStatistics;
  filter: XlsxFilterState;
  conditionalFormats: XlsxConditionalState;
  dataValidation: XlsxValidationState;
  printSetup: XlsxPrintSetup & { readOnlyReason: string };
  printRange: XlsxPrintRange & { readOnlyReason: string };
  headerFooter: XlsxHeaderFooter & { readOnlyReason: string };
  revision: number;
  mainPart: string;
  fontKeys: string[];
  normalFont: string;
  merging: {
    range: string;
    merged: boolean;
    discarded: number;
    discardedNotes: number;
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
  selection: { sheet: string; range: CellRange; address: string };
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
  view: {
    gridLines: boolean;
    headings: boolean;
    rtl: boolean;
    formulas: boolean;
    readOnlyReason: string;
  };
  formatting: XlsxFormatting;
  diagnostics: string[];
  date1904: boolean;
}

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
