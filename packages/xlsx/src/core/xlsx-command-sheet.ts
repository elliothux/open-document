import { type XlsxQuery } from "./xlsx-query.js";
import type {
  XlsxFormulaAssistance,
  XlsxFormulaDraft,
} from "./xlsx-formula.js";
import {
  checkXlsxSubtotalSettings,
  type XlsxSubtotals,
  type XlsxSubtotalSettings,
} from "./xlsx-subtotal.js";
import {
  checkXlsxConsolidateSettings,
  type XlsxConsolidation,
  type XlsxConsolidateSettings,
} from "./xlsx-consolidate.js";
import {
  checkXlsxPivotSettings,
  type XlsxPivotPreview,
  type XlsxPivots,
  type XlsxPivotSettings,
} from "./xlsx-pivot.js";
import {
  type XlsxSlicers,
  checkXlsxSlicerSettings,
  type XlsxSlicerSettings,
} from "./xlsx-slicer.js";
import {
  checkXlsxDrawingFrame,
  type XlsxDrawingFrame,
} from "./xlsx-drawing-frame.js";
import {
  type XlsxTimelines,
  checkXlsxTimelineSettings,
  type XlsxTimelineSettings,
} from "./xlsx-timeline.js";
import { protectionSalt } from "@open-document/wasm/abi/protection-password";
import {
  copiedCells,
  checkXlsxPasteMode,
  type CopiedCells,
  type XlsxPasteMode,
} from "./xlsx-clipboard.js";
import { checkXlsxSheetEdit, type XlsxSheetEdit } from "./xlsx-sheet.js";
import { type XlsxSelectionGeometry } from "./xlsx-geometry.js";
import {
  checkXlsxFillTarget,
  type XlsxFillTarget,
  type XlsxFillPreview,
} from "./xlsx-fill.js";
import {
  checkXlsxDuplicateSettings,
  type XlsxDuplicateSettings,
  type XlsxDuplicates,
} from "./xlsx-duplicates.js";
import {
  xlsxDelimitedOptions,
  checkXlsxTextColumnSettings,
  type XlsxDelimitedOptions,
  type XlsxTextColumnSettings,
  type XlsxTextColumns,
} from "./xlsx-delimited.js";
import { spreadsheetDate } from "./xlsx-filter.js";
import { DocumentError, type Budget } from "@open-document/wasm/abi/session";
import {
  xlsxFindOptions,
  type XlsxFindOptions,
  type XlsxSearchResult,
} from "./xlsx-search.js";
import { checkPrintOptions, type PrintOptions } from "./xlsx-print.js";
import { type CompactXlsxViewport, type XlsxPrintLayout } from "./xlsx-grid.js";
import {
  type XlsxDrawingSelection,
  type XlsxDrawingPreview,
  checkDrawingGesture,
  type XlsxDrawingGesture,
} from "./xlsx-drawing-pointer.js";
import {
  checkXlsxCellFormat,
  copiedCellFormat,
  type CopiedCellFormat,
  type XlsxCellFormat,
} from "./xlsx-format.js";
import type { XlsxRuntime } from "./xlsx-session.js";
import type { GridViewport, XlsxClearMode } from "./xlsx.js";
export const xlsxSheetCommands = {
  selectDrawingXlsx(
    session: XlsxRuntime,
    {
      revision,
      layout,
      objectId,
    }: { revision: number; layout: number; objectId: string | null },
  ) {
    return session.call<XlsxDrawingSelection>({
      operation: "selectDrawingXlsx",
      revision,
      layout,
      objectId,
    });
  },
  drawingGestureXlsx(
    session: XlsxRuntime,
    {
      revision,
      layout,
      gesture,
      profile,
    }: {
      revision: number;
      layout: number;
      gesture: XlsxDrawingGesture;
      profile: Record<string, string>;
    },
  ) {
    checkDrawingGesture(gesture);
    return session.call<XlsxDrawingPreview>({
      operation: "drawingGestureXlsx",
      revision,
      layout,
      ...gesture,
      profile,
    });
  },
  pivotsXlsx(
    session: XlsxRuntime,
    { revision, sheet }: { revision: number; sheet: string },
  ) {
    return session.call<XlsxPivots>({
      operation: "pivotsXlsx",
      revision,
      sheet,
    });
  },
  slicersXlsx(
    session: XlsxRuntime,
    { revision, sheet }: { revision: number; sheet: string },
  ) {
    return session.call<XlsxSlicers>({
      operation: "slicersXlsx",
      revision,
      sheet,
    });
  },
  insertXlsxSlicer(
    session: XlsxRuntime,
    {
      revision,
      sheet,
      settings,
      profile,
    }: {
      revision: number;
      sheet: string;
      settings: XlsxSlicerSettings;
      profile: Record<string, string>;
    },
  ) {
    checkXlsxSlicerSettings(settings);
    return session.call<XlsxQuery>({
      operation: "insertXlsxSlicer",
      revision,
      sheet,
      settings,
      profile,
    });
  },
  frameXlsxSlicer(
    session: XlsxRuntime,
    {
      revision,
      sheet,
      id,
      frame,
      profile,
    }: {
      revision: number;
      sheet: string;
      id: string;
      frame: XlsxDrawingFrame;
      profile: Record<string, string>;
    },
  ) {
    checkXlsxDrawingFrame(frame);
    return session.call<XlsxQuery>({
      operation: "frameXlsxSlicer",
      revision,
      sheet,
      objectId: id,
      frame,
      profile,
    });
  },
  timelinesXlsx(
    session: XlsxRuntime,
    { revision, sheet }: { revision: number; sheet: string },
  ) {
    return session.call<XlsxTimelines>({
      operation: "timelinesXlsx",
      revision,
      sheet,
    });
  },
  insertXlsxTimeline(
    session: XlsxRuntime,
    {
      revision,
      sheet,
      settings,
      profile,
    }: {
      revision: number;
      sheet: string;
      settings: XlsxTimelineSettings;
      profile: Record<string, string>;
    },
  ) {
    checkXlsxTimelineSettings(settings);
    return session.call<XlsxQuery>({
      operation: "insertXlsxTimeline",
      revision,
      sheet,
      settings,
      profile,
    });
  },
  pivotPreviewXlsx(
    session: XlsxRuntime,
    {
      revision,
      settings,
      part,
    }: {
      revision: number;
      settings: XlsxPivotSettings;
      part?: string | undefined;
    },
  ) {
    checkXlsxPivotSettings(settings);
    return session.call<XlsxPivotPreview>({
      operation: "pivotPreviewXlsx",
      revision,
      settings,
      part,
    });
  },
  findXlsx(
    session: XlsxRuntime,
    {
      revision,
      sheet,
      text,
      options = {},
    }: {
      revision: number;
      sheet: string;
      text: string;
      options?: XlsxFindOptions | undefined;
    },
  ): XlsxSearchResult {
    return session.call<XlsxSearchResult>({
      operation: "findXlsx",
      revision,
      sheet,
      text,
      options: xlsxFindOptions(options),
    });
  },
  replaceXlsxMatches(
    session: XlsxRuntime,
    {
      revision,
      sheet,
      text,
      options,
      replacement,
      index,
    }: {
      revision: number;
      sheet: string;
      text: string;
      options: XlsxFindOptions;
      replacement: string;
      index?: number | undefined;
    },
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
    return session.call<XlsxQuery>({
      operation: "replaceXlsxMatches",
      revision,
      sheet,
      text,
      options: xlsxFindOptions(options),
      replacement,
      index,
    });
  },
  autoFitXlsx(
    session: XlsxRuntime,
    {
      revision,
      sheet,
      first,
      last,
      axis,
      profile,
    }: {
      revision: number;
      sheet: string;
      first: number;
      last: number;
      axis: "rows" | "columns";
      profile: Record<string, string>;
    },
  ): XlsxQuery {
    return session.call<XlsxQuery>({
      operation: "autoFitXlsx",
      revision,
      sheet,
      first,
      last,
      axis,
      profile,
    });
  },
  captureXlsxFormat(
    session: XlsxRuntime,
    { revision }: { revision: number },
  ): CopiedCellFormat {
    return session.call<CopiedCellFormat>({
      operation: "captureXlsxFormat",
      revision,
    });
  },
  applyXlsxFormat(
    session: XlsxRuntime,
    { revision, format }: { revision: number; format: CopiedCellFormat },
  ): XlsxQuery {
    copiedCellFormat(format);
    return session.call<XlsxQuery>({
      operation: "applyXlsxFormat",
      revision,
      format,
    });
  },
  formatXlsxCells(
    session: XlsxRuntime,
    { revision, patch }: { revision: number; patch: XlsxCellFormat },
  ): XlsxQuery {
    checkXlsxCellFormat(patch);
    return session.call<XlsxQuery>({
      operation: "formatXlsxCells",
      revision,
      patch,
    });
  },
  editXlsxSheet(
    session: XlsxRuntime,
    {
      revision,
      sheet,
      change,
      date,
    }: {
      revision: number;
      sheet: string;
      change: XlsxSheetEdit;
      date?: string | undefined;
    },
  ): XlsxQuery {
    checkXlsxSheetEdit(change);
    return session.call<XlsxQuery>({
      operation: "editXlsxSheet",
      revision,
      sheet,
      change,
      date: spreadsheetDate(date),
      passwordSalt:
        change.action === "protection" || change.action === "workbookProtection"
          ? protectionSalt(change.enabled, change.password ?? "")
          : "",
    });
  },
  duplicatesXlsx(
    session: XlsxRuntime,
    {
      revision,
      sheet,
      settings,
    }: { revision: number; sheet: string; settings: XlsxDuplicateSettings },
  ): XlsxDuplicates {
    checkXlsxDuplicateSettings(settings);
    return session.call<XlsxDuplicates>({
      operation: "duplicatesXlsx",
      revision,
      sheet,
      settings,
    });
  },
  consolidationXlsx(
    session: XlsxRuntime,
    {
      revision,
      sheet,
      settings,
    }: { revision: number; sheet: string; settings: XlsxConsolidateSettings },
  ) {
    checkXlsxConsolidateSettings(settings);
    return session.call<XlsxConsolidation>({
      operation: "consolidationXlsx",
      revision,
      sheet,
      settings,
    });
  },
  subtotalsXlsx(
    session: XlsxRuntime,
    {
      revision,
      sheet,
      settings,
    }: { revision: number; sheet: string; settings: XlsxSubtotalSettings },
  ) {
    checkXlsxSubtotalSettings(settings);
    return session.call<XlsxSubtotals>({
      operation: "subtotalsXlsx",
      revision,
      sheet,
      settings,
    });
  },
  textColumnsXlsx(
    session: XlsxRuntime,
    {
      revision,
      sheet,
      settings,
    }: { revision: number; sheet: string; settings: XlsxTextColumnSettings },
  ): XlsxTextColumns {
    checkXlsxTextColumnSettings(settings);
    return session.call<XlsxTextColumns>({
      operation: "textColumnsXlsx",
      revision,
      sheet,
      settings,
    });
  },
  createXlsx(
    session: XlsxRuntime,
    { budget, date }: { budget: Budget; date?: string | undefined },
  ): XlsxQuery {
    return session.call<XlsxQuery>({
      operation: "createXlsx",
      randomSeed: crypto.getRandomValues(new Uint8Array(32)),
      budget,
      date: spreadsheetDate(date),
    });
  },
  importXlsxDelimited(
    session: XlsxRuntime,
    {
      bytes,
      delimiter,
      budget,
      options = {},
      date,
    }: {
      bytes: Uint8Array;
      delimiter: "," | "\t";
      budget: Budget;
      options?: XlsxDelimitedOptions | undefined;
      date?: string | undefined;
    },
  ): XlsxQuery {
    if (delimiter !== "," && delimiter !== "\t")
      throw new Error("Invalid delimiter");
    return session.call<XlsxQuery>({
      operation: "importXlsxDelimited",
      randomSeed: crypto.getRandomValues(new Uint8Array(32)),
      bytes,
      delimiter,
      budget,
      options: xlsxDelimitedOptions(options),
      date: spreadsheetDate(date),
    });
  },
  exportXlsxCsv(
    session: XlsxRuntime,
    {
      revision,
      selection = false,
    }: { revision: number; selection?: boolean | undefined },
  ): Uint8Array {
    if (typeof selection !== "boolean") throw new Error("Invalid CSV scope");
    return session.bytes({ operation: "exportXlsxCsv", revision, selection });
  },
  openXlsx(
    session: XlsxRuntime,
    {
      bytes,
      budget,
      date,
    }: { bytes: Uint8Array; budget: Budget; date?: string | undefined },
  ): XlsxQuery {
    if (bytes.length > budget.fileBytes || bytes.length > budget.retainedBytes)
      throw new DocumentError(
        "limit-exceeded",
        "Byte input exceeds budget",
        "",
        -1,
      );
    return session.call<XlsxQuery>({
      operation: "openXlsx",
      randomSeed: crypto.getRandomValues(new Uint8Array(32)),
      bytes,
      budget,
      date: spreadsheetDate(date),
    });
  },
  queryXlsx(
    session: XlsxRuntime,
    {
      sheet,
      range,
    }: { sheet?: string | undefined; range?: string | undefined },
  ): XlsxQuery {
    return session.call<XlsxQuery>({ operation: "queryXlsx", sheet, range });
  },
  selectXlsx(
    session: XlsxRuntime,
    {
      revision,
      sheet,
      range,
    }: { revision: number; sheet: string; range: string },
  ): XlsxQuery {
    return session.call<XlsxQuery>({
      operation: "selectXlsx",
      revision,
      sheet,
      range,
    });
  },
  replaceXlsx(
    session: XlsxRuntime,
    {
      revision,
      sheet,
      range,
      values,
      literal = false,
      acceptWarnings = false,
    }: {
      revision: number;
      sheet: string;
      range: string;
      values: string[][];
      literal?: boolean | undefined;
      acceptWarnings?: boolean | undefined;
    },
  ): XlsxQuery {
    if (typeof acceptWarnings !== "boolean")
      throw new Error("Invalid validation warning acceptance");
    return session.call<XlsxQuery>({
      operation: "replaceXlsx",
      revision,
      sheet,
      range,
      values,
      literal,
      acceptWarnings,
    });
  },
  recalculateXlsx(
    session: XlsxRuntime,
    { revision }: { revision: number },
  ): XlsxQuery {
    return session.call<XlsxQuery>({ operation: "recalculateXlsx", revision });
  },
  undoXlsx(
    session: XlsxRuntime,
    { revision }: { revision: number },
  ): XlsxQuery {
    return session.call<XlsxQuery>({ operation: "undoXlsx", revision });
  },
  redoXlsx(
    session: XlsxRuntime,
    { revision }: { revision: number },
  ): XlsxQuery {
    return session.call<XlsxQuery>({ operation: "redoXlsx", revision });
  },
  saveXlsx(session: XlsxRuntime, _command: Record<never, never>): Uint8Array {
    return session.bytes({ operation: "saveXlsx" });
  },
  viewportXlsx(
    session: XlsxRuntime,
    options: GridViewport,
  ): CompactXlsxViewport {
    return session.call<CompactXlsxViewport>({
      operation: "viewportXlsx",
      ...options,
      reveal: options.reveal ?? false,
      compactCells: true,
    });
  },
  hitXlsx(
    session: XlsxRuntime,
    { layoutId, x, y }: { layoutId: number; x: number; y: number },
  ): string {
    return session.call<{ address: string }>({
      operation: "hitXlsx",
      layoutId,
      x,
      y,
    }).address;
  },
  selectionXlsx(
    session: XlsxRuntime,
    { layoutId }: { layoutId: number },
  ): XlsxSelectionGeometry {
    return session.call<XlsxSelectionGeometry>({
      operation: "selectionXlsx",
      layoutId,
    });
  },
  formulaAssistXlsx(
    session: XlsxRuntime,
    draft: XlsxFormulaDraft,
  ): XlsxFormulaAssistance {
    return session.call<XlsxFormulaAssistance>({
      operation: "formulaAssistXlsx",
      ...draft,
    });
  },
  numberFormatSamplesXlsx(
    session: XlsxRuntime,
    { formats }: { formats: readonly string[] },
  ): string[] {
    return session.call<string[]>({
      operation: "numberFormatSamplesXlsx",
      formats,
    });
  },
  fillPreviewXlsx(
    session: XlsxRuntime,
    { layoutId, target }: { layoutId: number; target: XlsxFillTarget },
  ): XlsxFillPreview {
    checkXlsxFillTarget(target);
    return session.call<XlsxFillPreview>({
      operation: "fillPreviewXlsx",
      layoutId,
      target,
    });
  },
  navigateXlsx(
    session: XlsxRuntime,
    {
      revision,
      direction,
      extend = false,
    }: {
      revision: number;
      direction: "left" | "right" | "up" | "down" | "home";
      extend?: boolean | undefined;
    },
  ): XlsxQuery {
    return session.call<XlsxQuery>({
      operation: "navigateXlsx",
      revision,
      direction,
      extend,
    });
  },
  copyXlsx(session: XlsxRuntime, { revision }: { revision: number }): string {
    return session.call<{ text: string }>({ operation: "copyXlsx", revision })
      .text;
  },
  captureXlsxCells(
    session: XlsxRuntime,
    { revision }: { revision: number },
  ): CopiedCells {
    return session.call<CopiedCells>({
      operation: "captureXlsxCells",
      revision,
    });
  },
  pasteXlsxCells(
    session: XlsxRuntime,
    {
      revision,
      copied,
      mode = "all",
      transpose = false,
      acceptWarnings = false,
    }: {
      revision: number;
      copied: CopiedCells;
      mode?: XlsxPasteMode | undefined;
      transpose?: boolean | undefined;
      acceptWarnings?: boolean | undefined;
    },
  ): XlsxQuery {
    copiedCells(copied);
    checkXlsxPasteMode(mode);
    if (typeof transpose !== "boolean" || typeof acceptWarnings !== "boolean")
      throw new Error("Invalid cell paste options");
    return session.call<XlsxQuery>({
      operation: "pasteXlsxCells",
      revision,
      copied,
      mode,
      transpose,
      acceptWarnings,
    });
  },
  pasteXlsx(
    session: XlsxRuntime,
    {
      revision,
      text,
      acceptWarnings = false,
    }: { revision: number; text: string; acceptWarnings?: boolean | undefined },
  ): XlsxQuery {
    if (typeof acceptWarnings !== "boolean")
      throw new Error("Invalid validation warning acceptance");
    return session.call<XlsxQuery>({
      operation: "pasteXlsx",
      revision,
      text,
      acceptWarnings,
    });
  },
  clearXlsx(
    session: XlsxRuntime,
    {
      revision,
      mode = "contents",
    }: { revision: number; mode?: XlsxClearMode | undefined },
  ): XlsxQuery {
    return session.call<XlsxQuery>({ operation: "clearXlsx", revision, mode });
  },
  printXlsx(
    session: XlsxRuntime,
    {
      revision,
      sheet,
      options,
      profile,
    }: {
      revision: number;
      sheet: string;
      options: PrintOptions | null;
      profile: Record<string, string>;
    },
  ): XlsxPrintLayout {
    checkPrintOptions(options);
    return session.call<XlsxPrintLayout>({
      operation: "printXlsx",
      revision,
      sheet,
      options,
      profile,
    });
  },
  exportXlsxPdf(
    session: XlsxRuntime,
    { layoutId, outputBytes }: { layoutId: number; outputBytes: number },
  ): Uint8Array {
    return session.bytes({ operation: "exportXlsxPdf", layoutId, outputBytes });
  },
};
