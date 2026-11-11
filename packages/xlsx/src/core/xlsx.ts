export * from "./xlsx-subtotal.js";
export * from "./xlsx-consolidate.js";

export * from "./xlsx-comments.js";
export * from "./xlsx-shapes.js";
export * from "./xlsx-charts.js";
export * from "./xlsx-pictures.js";
export * from "./xlsx-pivot.js";
export * from "./xlsx-slicer.js";
export {
  checkXlsxDrawingFrame,
  type XlsxDrawingFrame,
} from "./xlsx-drawing-frame.js";
export * from "./xlsx-timeline.js";
export type { XlsxSlicerView } from "./xlsx-slicer-view.js";
export type { XlsxQuery } from "./xlsx-query.js";
export type { XlsxProtection } from "./xlsx-protection.js";
export * from "./xlsx-clipboard.js";
export {
  checkXlsxHyperlinkTarget,
  type XlsxHyperlink,
  type XlsxNote,
} from "./xlsx-sheet.js";
export type { XlsxSelectionGeometry } from "./xlsx-geometry.js";
export {
  checkXlsxFillTarget,
  type XlsxFillTarget,
  type XlsxFillPreview,
} from "./xlsx-fill.js";
export type { XlsxName, XlsxNames, XlsxNameEdit } from "./xlsx-names.js";
export * from "./xlsx-tables.js";
export * from "./xlsx-outline.js";
export type { XlsxStatistics } from "./xlsx-statistics.js";
export type { XlsxSortSettings, XlsxSortKey } from "./xlsx-sort.js";
export * from "./xlsx-duplicates.js";
export * from "./xlsx-delimited.js";
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
import { checkDrawingFragment } from "./xlsx-drawing-clipboard.js";
export { checkDrawingFragment };
export type { XlsxDrawingClipboard } from "./xlsx-drawing-clipboard.js";

export { xlsxFindOptions } from "./xlsx-search.js";
export type { XlsxFindOptions, XlsxSearchResult } from "./xlsx-search.js";
export { checkXlsxPrintSetup, checkPrintOptions } from "./xlsx-print.js";
export type {
  PrintOptions,
  XlsxPrintSetup,
  XlsxPrintRange,
  XlsxHeaderFooter,
} from "./xlsx-print.js";

export { checkDrawingGesture } from "./xlsx-drawing-pointer.js";
export type {
  XlsxDrawingSelection,
  XlsxDrawingGesture,
  XlsxDrawingPreview,
  XlsxAnalysisPreview,
} from "./xlsx-drawing-pointer.js";
export type { XlsxViewport, XlsxPrintLayout } from "./xlsx-grid.js";
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
  /** Device pixels per point for screen-only chart text. */
  screenScale?: number;
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
export { XlsxSession } from "./xlsx-session.js";
export type { XlsxCommand, XlsxResult } from "./xlsx-command.js";
export type {
  XlsxFormulaAssistance,
  XlsxFormulaDraft,
  XlsxFormulaSignature,
} from "./xlsx-formula.js";
import {
  checkByteInput,
  type InputLimits,
} from "@open-document/wasm/abi/session";
import type { XlsxCommand } from "./xlsx-command.js";

export interface XlsxInputLimits extends InputLimits {
  readonly exportBytes: number;
  readonly drawingFragmentUnits: number;
  readonly imageBytes: number;
  readonly rgbaBytes: number;
  readonly delimitedBytes: number;
}

/** Apply core input ceilings before encoding or Worker cloning. */
export function checkXlsxByteInput(
  command: XlsxCommand,
  limits: XlsxInputLimits,
): void {
  if (
    command.operation === "drawingFragmentImageXlsx" ||
    command.operation === "pasteDrawingXlsx"
  ) {
    checkDrawingFragment(command.fragment, limits.drawingFragmentUnits);
    return;
  }
  if (!("bytes" in command)) return;
  let ceiling = limits.imageBytes;
  if (command.operation === "imageXlsx") ceiling = limits.rgbaBytes;
  else if (command.operation === "openXlsx")
    ceiling = Math.min(command.budget.fileBytes, command.budget.retainedBytes);
  else if (command.operation === "importXlsxDelimited")
    ceiling = Math.min(
      command.budget.fileBytes,
      command.budget.retainedBytes,
      limits.delimitedBytes,
    );
  checkByteInput(command.bytes, ceiling);
}
