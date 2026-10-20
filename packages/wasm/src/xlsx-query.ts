import type { XlsxTable, XlsxTableStyleChoice } from "./xlsx-tables.js";
import type { XlsxOutline } from "./xlsx-outline.js";
import type { XlsxHyperlink, XlsxNote } from "./xlsx-sheet.js";
import type { XlsxNames } from "./xlsx-names.js";
import type { XlsxStatistics } from "./xlsx-statistics.js";
import type { XlsxFilterState } from "./xlsx-filter.js";
import type { XlsxConditionalState } from "./xlsx-conditional.js";
import type { XlsxValidationState } from "./xlsx-validation.js";
import type {
  XlsxPrintSetup,
  XlsxPrintRange,
  XlsxHeaderFooter,
} from "./xlsx-print.js";
import type { XlsxFormatting } from "./xlsx-format.js";
import type { CellRange, XlsxCell } from "./xlsx.js";
import type { XlsxProtection } from "./xlsx-protection.js";

export interface XlsxQuery {
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
