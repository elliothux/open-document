import type { EngineHandle } from "@open-document/wasm";
import { engineModule } from "@open-document/wasm/loader";
import { type Budget } from "@open-document/wasm/abi/session";
import type { Connection } from "@open-document/web-core/connection";
import type {
  OfficeCommand,
  WorkerOperation,
} from "@open-document/web-core/protocol";
import { openWorkerConnection } from "@open-document/web-core/worker-connection";
import {
  decodeXlsxResult,
  type XlsxCommand,
  type XlsxResult,
} from "../core/xlsx-command.js";
import { spreadsheetDate } from "../core/xlsx-filter.js";
import { resetCellClipboard } from "./spreadsheet-clipboard.js";

export * from "../core/xlsx-comments.js";
export {
  checkXlsxSubtotalSettings,
  subtotalFunctions,
  type XlsxSubtotalSettings,
  type XlsxSubtotals,
} from "../core/xlsx.js";
export {
  checkXlsxConsolidateSettings,
  consolidateFunctions,
  type XlsxConsolidateSettings,
  type XlsxConsolidation,
} from "../core/xlsx.js";
export {
  type XlsxTimeline,
  checkXlsxTimelineSettings,
  type XlsxTimelineSettings,
  type XlsxTimelineRange,
  type XlsxTimelineEdit,
  type XlsxTimelineView,
  type XlsxTimelineGesture,
  type XlsxAnalysisPreview,
  type XlsxTimelines,
} from "../core/xlsx.js";
export {
  checkXlsxSlicerSettings,
  checkXlsxDrawingFrame,
} from "../core/xlsx.js";
export type {
  XlsxSlicer,
  XlsxSlicerMember,
  XlsxSlicers,
  XlsxSlicerEdit,
  XlsxSlicerView,
  XlsxSlicerGesture,
  XlsxSlicerSettings,
  XlsxDrawingFrame,
} from "../core/xlsx.js";
export {
  xlsxChartKinds,
  checkXlsxChartSettings,
  checkXlsxChartFrame,
} from "../core/xlsx.js";
export type {
  XlsxChartSettings,
  XlsxDrawingClipboard,
  XlsxChartFrame,
  XlsxChart,
  XlsxCharts,
} from "../core/xlsx.js";
export { xlsxShapeKinds, checkXlsxShapeSettings } from "../core/xlsx.js";
export type {
  XlsxShapeKind,
  XlsxShapeSettings,
  XlsxShape,
  XlsxShapes,
} from "../core/xlsx.js";

export type {
  XlsxPictureSettings,
  XlsxPicture,
  XlsxPictures,
  XlsxDrawingSelection,
  XlsxDrawingGesture,
  XlsxDrawingPreview,
} from "../core/xlsx.js";
export {
  xlsxPivotAggregates,
  xlsxPivotValueModes,
  xlsxPivotBaseModes,
  xlsxPivotCompareModes,
  xlsxPivotDateUnits,
  checkXlsxPivotSettings,
} from "../core/xlsx.js";
export type {
  XlsxPivotSettings,
  XlsxPivotFilter,
  XlsxPivotNumberGroup,
  XlsxPivotDateGroup,
  XlsxPivotValue,
  XlsxPivotBaseItem,
  XlsxPivotPreview,
  XlsxPivots,
  XlsxPivotEdit,
} from "../core/xlsx.js";

export type { XlsxProtection } from "../core/xlsx.js";
export type {
  XlsxSparkline,
  XlsxSparklineKind,
  XlsxSparklineEdit,
  XlsxSparklines,
} from "../core/xlsx.js";
export type {
  CopiedCell,
  CopiedCells,
  CopiedConditional,
  CopiedValidation,
  CopiedHyperlink,
  CopiedNotes,
  CopiedSparkline,
  XlsxPasteMode,
} from "../core/xlsx.js";

export type { XlsxSheetEdit, XlsxClearMode } from "../core/xlsx.js";
export type {
  XlsxOutline,
  XlsxTable,
  XlsxTableColumn,
  XlsxTableEdit,
  XlsxTableTotal,
  XlsxTableStyle,
  XlsxTableStyleElement,
  XlsxTableStyleChoice,
  XlsxTableTotalFunction,
  XlsxOutlineGroup,
  XlsxOutlineEdit,
} from "../core/xlsx.js";
export {
  checkXlsxTextColumnSettings,
  xlsxTableStyleRegions,
} from "../core/xlsx.js";
export type { XlsxTextColumnType } from "../core/xlsx.js";
export type { XlsxTextColumnSettings, XlsxTextColumns } from "../core/xlsx.js";
export type { XlsxFillTarget, XlsxFillPreview } from "../core/xlsx.js";
export type { XlsxStatistics } from "../core/xlsx.js";
export type { XlsxDuplicateSettings, XlsxDuplicates } from "../core/xlsx.js";
export {
  checkXlsxSheetEdit,
  checkXlsxHyperlinkTarget,
  type XlsxHyperlink,
  type XlsxNote,
} from "../core/xlsx.js";
export type { XlsxName, XlsxNames, XlsxNameEdit } from "../core/xlsx.js";
export type { XlsxSortSettings, XlsxSortKey } from "../core/xlsx.js";
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
} from "../core/xlsx.js";
export { xlsxRelativeDatePeriods, spreadsheetDate } from "../core/xlsx.js";
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
} from "../core/xlsx.js";
export {
  conditionalThresholds,
  conditionalDatePeriods,
  conditionalIconSets,
} from "../core/xlsx.js";
export { validationKinds, validationOperators } from "../core/xlsx.js";
export type { XlsxDataValidation, XlsxValidationState } from "../core/xlsx.js";
export type {
  XlsxPrintSetup,
  XlsxPrintRange,
  XlsxHeaderFooter,
  XlsxDelimitedOptions,
  XlsxFindOptions,
  XlsxSearchResult,
} from "../core/xlsx.js";
export { xlsxNumberFormats, xlsxBorderStyles } from "../core/xlsx.js";
export type {
  XlsxCellFormat,
  XlsxFormatting,
  XlsxCellBorder,
  CopiedCellFormat,
  XlsxSelectionGeometry,
} from "../core/xlsx.js";

export type XlsxOperation = WorkerOperation<OfficeCommand<XlsxCommand>>;

/** Browser workbook transport; one Worker owns the complete core session. */
export class XlsxClient {
  private constructor(
    private readonly connection: Connection<XlsxOperation, XlsxInputLimits>,
  ) {}
  static async open(
    engine: EngineHandle,
    workerUrl: URL,
    signal?: AbortSignal,
  ): Promise<XlsxClient> {
    return new XlsxClient(
      await openWorkerConnection<XlsxOperation, XlsxInputLimits>(
        engineModule(engine),
        workerUrl,
        signal,
      ),
    );
  }
  async defaultBudget(): Promise<Budget> {
    return (await this.connection.request({ operation: "budget" })) as Budget;
  }
  async addFont(bytes: Uint8Array, identity: string): Promise<void> {
    await this.connection.request({ operation: "font", bytes, identity });
  }
  inputLimits(): XlsxInputLimits {
    return this.connection.inputLimits();
  }
  async execute<C extends XlsxCommand>(command: C): Promise<XlsxResult<C>> {
    checkXlsxByteInput(command, this.connection.inputLimits());
    if (
      command.operation === "openXlsx" ||
      command.operation === "createXlsx" ||
      command.operation === "importXlsxDelimited"
    )
      resetCellClipboard(this);
    const request =
      command.operation === "openXlsx" ||
      command.operation === "createXlsx" ||
      command.operation === "importXlsxDelimited" ||
      command.operation === "editXlsxSheet"
        ? { ...command, date: spreadsheetDate(command.date) }
        : command;
    return decodeXlsxResult(command, await this.connection.request(request));
  }
  dispose(): void {
    this.connection.dispose();
  }
}
import { checkXlsxByteInput, type XlsxInputLimits } from "../core/xlsx.js";
export type { XlsxInputLimits } from "../core/xlsx.js";
