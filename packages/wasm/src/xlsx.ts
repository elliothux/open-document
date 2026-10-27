import { xlsxQuery, type XlsxQuery } from "./xlsx-query.js";
import { record } from "./validation.js";
import {
  checkXlsxSubtotalSettings,
  xlsxSubtotals,
  type XlsxSubtotalSettings,
} from "./xlsx-subtotal.js";
export * from "./xlsx-subtotal.js";
import {
  checkXlsxConsolidateSettings,
  xlsxConsolidation,
  type XlsxConsolidateSettings,
} from "./xlsx-consolidate.js";
export * from "./xlsx-consolidate.js";
import { XlsxDrawingSession } from "./xlsx-drawings.js";
export * from "./xlsx-comments.js";
export * from "./xlsx-shapes.js";
export * from "./xlsx-charts.js";
export * from "./xlsx-pictures.js";
export { xlsxQuery } from "./xlsx-query.js";
import {
  checkXlsxPivotSettings,
  xlsxPivotPreview,
  xlsxPivots,
  type XlsxPivotSettings,
} from "./xlsx-pivot.js";
export * from "./xlsx-pivot.js";
import {
  xlsxSlicers,
  checkXlsxSlicerSettings,
  type XlsxSlicerSettings,
} from "./xlsx-slicer.js";
export * from "./xlsx-slicer.js";
import {
  checkXlsxDrawingFrame,
  type XlsxDrawingFrame,
} from "./xlsx-drawing-frame.js";
export {
  checkXlsxDrawingFrame,
  type XlsxDrawingFrame,
} from "./xlsx-drawing-frame.js";
import {
  xlsxTimelines,
  checkXlsxTimelineSettings,
  type XlsxTimelineSettings,
} from "./xlsx-timeline.js";
export * from "./xlsx-timeline.js";
export type { XlsxSlicerView } from "./xlsx-slicer-view.js";
export type { XlsxQuery } from "./xlsx-query.js";
import { protectionSalt } from "./protection-password.js";
export type { XlsxProtection } from "./xlsx-protection.js";
import {
  copiedCells,
  checkXlsxPasteMode,
  type CopiedCells,
  type XlsxPasteMode,
} from "./xlsx-clipboard.js";
export * from "./xlsx-clipboard.js";
import { checkXlsxSheetEdit, type XlsxSheetEdit } from "./xlsx-sheet.js";
export {
  checkXlsxHyperlinkTarget,
  xlsxHyperlink,
  type XlsxHyperlink,
  type XlsxNote,
  xlsxNote,
} from "./xlsx-sheet.js";
import { xlsxSelection, type XlsxSelectionGeometry } from "./xlsx-geometry.js";
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
export type { XlsxName, XlsxNames, XlsxNameEdit } from "./xlsx-names.js";
export * from "./xlsx-tables.js";
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
import { spreadsheetDate } from "./xlsx-filter.js";
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
  XlsxIconFilter,
  XlsxFilterSettings,
  XlsxFilterState,
} from "./xlsx-filter.js";
export {
  checkXlsxConditionalFormat,
  conditionalThresholds,
  conditionalDatePeriods,
  conditionalIconSets,
} from "./xlsx-conditional.js";
export type {
  XlsxConditionalFormat,
  XlsxConditionalRank,
  XlsxConditionalAverage,
  XlsxConditionalRule,
  XlsxConditionalState,
  XlsxConditionalStop,
  XlsxConditionalThreshold,
  XlsxDataBar,
  XlsxIconSet,
  XlsxIconThreshold,
} from "./xlsx-conditional.js";
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
export {
  checkDrawingFragment,
  drawingClipboard,
} from "./xlsx-drawing-clipboard.js";
export type { XlsxDrawingClipboard } from "./xlsx-drawing-clipboard.js";
import { encodeBytes } from "./session.js";
import { DocumentError, type Budget } from "./foundation.js";
import {
  xlsxFindOptions,
  xlsxSearchResult,
  type XlsxFindOptions,
  type XlsxSearchResult,
} from "./xlsx-search.js";
export { xlsxFindOptions, xlsxSearchResult } from "./xlsx-search.js";
export type { XlsxFindOptions, XlsxSearchResult } from "./xlsx-search.js";
import { checkPrintOptions, type PrintOptions } from "./xlsx-print.js";
export { checkXlsxPrintSetup, checkPrintOptions } from "./xlsx-print.js";
export type {
  PrintOptions,
  XlsxPrintSetup,
  XlsxPrintRange,
  XlsxHeaderFooter,
} from "./xlsx-print.js";
import {
  xlsxPrintLayout,
  xlsxViewport,
  type XlsxPrintLayout,
  type XlsxViewport,
} from "./xlsx-grid.js";
import {
  xlsxDrawingSelection,
  xlsxDrawingPreview,
  checkDrawingGesture,
  type XlsxDrawingGesture,
} from "./xlsx-drawing-pointer.js";
export {
  xlsxDrawingSelection,
  xlsxDrawingPreview,
  checkDrawingGesture,
  xlsxAnalysisPreview,
} from "./xlsx-drawing-pointer.js";
export type {
  XlsxDrawingSelection,
  XlsxDrawingGesture,
  XlsxDrawingPreview,
  XlsxAnalysisPreview,
} from "./xlsx-drawing-pointer.js";
export { xlsxPrintLayout, xlsxViewport } from "./xlsx-grid.js";
export type { XlsxViewport, XlsxPrintLayout } from "./xlsx-grid.js";
import {
  checkXlsxCellFormat,
  copiedCellFormat,
  type CopiedCellFormat,
  type XlsxCellFormat,
} from "./xlsx-format.js";
export {
  checkXlsxCellFormat,
  xlsxNumberFormats,
  xlsxBorderStyles,
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
  /** Ephemeral native member hover; does not edit the workbook or print output. */
  slicerHover?: { object: string; index: number };
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

/** One workbook owner; values, XML transactions and history stay in MoonBit. */
export class XlsxSession extends XlsxDrawingSession {
  selectDrawing(revision: number, layout: number, objectId: string | null) {
    return xlsxDrawingSelection(
      this.call({
        operation: "selectDrawingXlsx",
        revision,
        layout,
        objectId,
      }),
    );
  }
  drawingGesture(
    revision: number,
    layout: number,
    gesture: XlsxDrawingGesture,
    profile: Record<string, string>,
  ) {
    checkDrawingGesture(gesture);
    return xlsxDrawingPreview(
      this.call({
        operation: "drawingGestureXlsx",
        revision,
        layout,
        ...gesture,
        profile,
      }),
    );
  }
  pivots(revision: number, sheet: string) {
    return xlsxPivots(this.call({ operation: "pivotsXlsx", revision, sheet }));
  }
  slicers(revision: number, sheet: string) {
    return xlsxSlicers(
      this.call({ operation: "slicersXlsx", revision, sheet }),
    );
  }
  insertSlicer(
    revision: number,
    sheet: string,
    settings: XlsxSlicerSettings,
    profile: Record<string, string>,
  ) {
    checkXlsxSlicerSettings(settings);
    return xlsxQuery(
      this.call({
        operation: "insertXlsxSlicer",
        revision,
        sheet,
        settings,
        profile,
      }),
    );
  }
  setSlicerFrame(
    revision: number,
    sheet: string,
    id: string,
    frame: XlsxDrawingFrame,
    profile: Record<string, string>,
  ) {
    checkXlsxDrawingFrame(frame);
    return xlsxQuery(
      this.call({
        operation: "frameXlsxSlicer",
        revision,
        sheet,
        objectId: id,
        frame,
        profile,
      }),
    );
  }
  timelines(revision: number, sheet: string) {
    return xlsxTimelines(
      this.call({ operation: "timelinesXlsx", revision, sheet }),
    );
  }
  insertTimeline(
    revision: number,
    sheet: string,
    settings: XlsxTimelineSettings,
    profile: Record<string, string>,
  ) {
    checkXlsxTimelineSettings(settings);
    return xlsxQuery(
      this.call({
        operation: "insertXlsxTimeline",
        revision,
        sheet,
        settings,
        profile,
      }),
    );
  }
  pivotPreview(revision: number, settings: XlsxPivotSettings, part?: string) {
    checkXlsxPivotSettings(settings);
    return xlsxPivotPreview(
      this.call({ operation: "pivotPreviewXlsx", revision, settings, part }),
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
  consolidation(
    revision: number,
    sheet: string,
    settings: XlsxConsolidateSettings,
  ) {
    checkXlsxConsolidateSettings(settings);
    return xlsxConsolidation(
      this.call({ operation: "consolidationXlsx", revision, sheet, settings }),
    );
  }
  subtotals(revision: number, sheet: string, settings: XlsxSubtotalSettings) {
    checkXlsxSubtotalSettings(settings);
    return xlsxSubtotals(
      this.call({ operation: "subtotalsXlsx", revision, sheet, settings }),
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
