import { Connection } from "./connection.js";
import {
  xlsxQuery,
  checkXlsxDuplicateSettings,
  xlsxDuplicates,
  type XlsxDuplicateSettings,
  type XlsxDuplicates,
  checkXlsxTextColumnSettings,
  xlsxTextColumns,
  type XlsxTextColumnSettings,
  type XlsxTextColumns,
  xlsxFindOptions,
  xlsxDelimitedOptions,
  type XlsxDelimitedOptions,
  xlsxSearchResult,
  type XlsxFindOptions,
  type XlsxSearchResult,
  checkXlsxSheetEdit,
  type XlsxSheetEdit,
  type XlsxClearMode,
  checkXlsxCellFormat,
  copiedCellFormat,
  type CopiedCellFormat,
  type XlsxCellFormat,
  xlsxViewport,
  xlsxPrintLayout,
  xlsxSelection,
  checkXlsxFillTarget,
  xlsxFillPreview,
  type XlsxFillTarget,
  type XlsxFillPreview,
  type XlsxQuery,
  type GridViewport,
  type XlsxViewport,
  type PrintOptions,
  type XlsxPrintLayout,
  type XlsxSelectionGeometry,
} from "@open-document/wasm/xlsx";
import { resourceBudget, type Budget } from "@open-document/wasm/foundation";
export type { XlsxSheetEdit, XlsxClearMode } from "@open-document/wasm/xlsx";
export { checkXlsxTextColumnSettings } from "@open-document/wasm/xlsx";
export type { XlsxTextColumnType } from "@open-document/wasm/xlsx";
export type {
  XlsxTextColumnSettings,
  XlsxTextColumns,
} from "@open-document/wasm/xlsx";
export type { XlsxFillTarget, XlsxFillPreview } from "@open-document/wasm/xlsx";
export type { XlsxStatistics } from "@open-document/wasm/xlsx";
export type {
  XlsxDuplicateSettings,
  XlsxDuplicates,
} from "@open-document/wasm/xlsx";
export {
  checkXlsxSheetEdit,
  checkXlsxHyperlinkTarget,
  type XlsxHyperlink,
  type XlsxNote,
} from "@open-document/wasm/xlsx";
export type {
  XlsxName,
  XlsxNames,
  XlsxNameEdit,
} from "@open-document/wasm/xlsx";
export type { XlsxSortSettings, XlsxSortKey } from "@open-document/wasm/xlsx";
export type {
  XlsxFilterValues,
  XlsxFilterColumn,
  XlsxFilterCondition,
  XlsxFilterOperator,
  XlsxCustomFilter,
  XlsxRankFilter,
  XlsxFilterSettings,
  XlsxFilterState,
} from "@open-document/wasm/xlsx";
export type {
  XlsxConditionalFormat,
  XlsxConditionalRule,
  XlsxConditionalState,
  XlsxConditionalStop,
  XlsxConditionalThreshold,
  XlsxDataBar,
} from "@open-document/wasm/xlsx";
export { conditionalThresholds } from "@open-document/wasm/xlsx";
export { validationKinds, validationOperators } from "@open-document/wasm/xlsx";
export type {
  XlsxDataValidation,
  XlsxValidationState,
} from "@open-document/wasm/xlsx";
export type {
  XlsxPrintSetup,
  XlsxPrintRange,
  XlsxHeaderFooter,
  XlsxDelimitedOptions,
  XlsxFindOptions,
  XlsxSearchResult,
} from "@open-document/wasm/xlsx";
export { xlsxNumberFormats } from "@open-document/wasm/xlsx";
export type {
  XlsxCellFormat,
  XlsxFormatting,
  XlsxCellBorder,
  CopiedCellFormat,
  XlsxSelectionGeometry,
} from "@open-document/wasm/xlsx";

/** Browser workbook transport; one Worker owns the complete core session. */
export class XlsxClient {
  async find(
    revision: number,
    sheet: string,
    text: string,
    options: XlsxFindOptions = {},
  ): Promise<XlsxSearchResult> {
    return xlsxSearchResult(
      await this.connection.request({
        operation: "findXlsx",
        revision,
        sheet,
        text,
        options: xlsxFindOptions(options),
      }),
    );
  }
  async replaceMatches(
    revision: number,
    sheet: string,
    text: string,
    options: XlsxFindOptions,
    replacement: string,
    index?: number,
  ): Promise<XlsxQuery> {
    return xlsxQuery(
      await this.connection.request({
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
  async autoFit(
    revision: number,
    sheet: string,
    first: number,
    last: number,
    axis: "rows" | "columns",
    profile: Record<string, string>,
  ): Promise<XlsxQuery> {
    return xlsxQuery(
      await this.connection.request({
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
  async captureFormat(revision: number): Promise<CopiedCellFormat> {
    return copiedCellFormat(
      await this.connection.request({
        operation: "captureXlsxFormat",
        revision,
      }),
    );
  }
  async applyFormat(
    revision: number,
    format: CopiedCellFormat,
  ): Promise<XlsxQuery> {
    copiedCellFormat(format);
    return xlsxQuery(
      await this.connection.request({
        operation: "applyXlsxFormat",
        revision,
        format,
      }),
    );
  }
  async formatCells(
    revision: number,
    patch: XlsxCellFormat,
  ): Promise<XlsxQuery> {
    checkXlsxCellFormat(patch);
    return xlsxQuery(
      await this.connection.request({
        operation: "formatXlsxCells",
        revision,
        patch,
      }),
    );
  }
  private constructor(private readonly connection: Connection) {}

  static async open(
    wasm: ArrayBuffer,
    workerUrl: URL,
    signal?: AbortSignal,
  ): Promise<XlsxClient> {
    const client = new XlsxClient(
      new Connection(new Worker(workerUrl, { type: "module" })),
    );
    try {
      await client.connection.initialize(
        { operation: "openSpreadsheet", wasm },
        signal,
      );
      return client;
    } catch (error) {
      client.dispose();
      throw error;
    }
  }
  async defaultBudget(): Promise<Budget> {
    return resourceBudget(
      await this.connection.request({ operation: "budget" }),
    );
  }
  async addFont(bytes: Uint8Array, identity: string): Promise<void> {
    await this.connection.request({ operation: "font", bytes, identity });
  }
  async create(budget: Budget): Promise<XlsxQuery> {
    return xlsxQuery(
      await this.connection.request({ operation: "createXlsx", budget }),
    );
  }
  async importDelimited(
    bytes: Uint8Array,
    delimiter: "," | "\t",
    budget: Budget,
    options: XlsxDelimitedOptions = {},
  ): Promise<XlsxQuery> {
    if (delimiter !== "," && delimiter !== "\t")
      throw new Error("Invalid delimiter");
    if (
      bytes.length > Math.min(budget.fileBytes, budget.retainedBytes, 4194304)
    )
      throw new Error("Delimited input exceeds budget");
    return xlsxQuery(
      await this.connection.request({
        operation: "importXlsxDelimited",
        bytes,
        delimiter,
        budget,
        options: xlsxDelimitedOptions(options),
      }),
    );
  }
  async exportCsv(revision: number, selection = false): Promise<Uint8Array> {
    if (typeof selection !== "boolean") throw new Error("Invalid CSV scope");
    const bytes = await this.connection.request({
      operation: "exportXlsxCsv",
      revision,
      selection,
    });
    if (!(bytes instanceof Uint8Array)) throw new Error("Invalid CSV bytes");
    return bytes;
  }
  async openXlsx(bytes: Uint8Array, budget: Budget): Promise<XlsxQuery> {
    return xlsxQuery(
      await this.connection.request({ operation: "openXlsx", bytes, budget }),
    );
  }
  async query(sheet?: string, range?: string): Promise<XlsxQuery> {
    return xlsxQuery(
      await this.connection.request({ operation: "queryXlsx", sheet, range }),
    );
  }
  async select(
    revision: number,
    sheet: string,
    range: string,
  ): Promise<XlsxQuery> {
    return xlsxQuery(
      await this.connection.request({
        operation: "selectXlsx",
        revision,
        sheet,
        range,
      }),
    );
  }
  async editSheet(
    revision: number,
    sheet: string,
    change: XlsxSheetEdit,
  ): Promise<XlsxQuery> {
    checkXlsxSheetEdit(change);
    return xlsxQuery(
      await this.connection.request({
        operation: "editXlsxSheet",
        revision,
        sheet,
        change,
      }),
    );
  }
  async duplicates(
    revision: number,
    sheet: string,
    settings: XlsxDuplicateSettings,
  ): Promise<XlsxDuplicates> {
    checkXlsxDuplicateSettings(settings);
    return xlsxDuplicates(
      await this.connection.request({
        operation: "duplicatesXlsx",
        revision,
        sheet,
        settings,
      }),
    );
  }
  async textColumns(
    revision: number,
    sheet: string,
    settings: XlsxTextColumnSettings,
  ): Promise<XlsxTextColumns> {
    checkXlsxTextColumnSettings(settings);
    return xlsxTextColumns(
      await this.connection.request({
        operation: "textColumnsXlsx",
        revision,
        sheet,
        settings,
      }),
    );
  }
  async replace(
    revision: number,
    sheet: string,
    range: string,
    values: string[][],
    literal = false,
    acceptWarnings = false,
  ): Promise<XlsxQuery> {
    if (typeof acceptWarnings !== "boolean")
      throw new Error("Invalid validation warning acceptance");
    return xlsxQuery(
      await this.connection.request({
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
  async undo(revision: number): Promise<XlsxQuery> {
    return xlsxQuery(
      await this.connection.request({ operation: "undoXlsx", revision }),
    );
  }
  async redo(revision: number): Promise<XlsxQuery> {
    return xlsxQuery(
      await this.connection.request({ operation: "redoXlsx", revision }),
    );
  }
  async save(): Promise<Uint8Array> {
    const bytes = await this.connection.request({ operation: "saveXlsx" });
    if (!(bytes instanceof Uint8Array))
      throw new Error("Invalid workbook bytes");
    return bytes;
  }
  dispose(): void {
    this.connection.dispose();
  }
  async viewport(options: GridViewport): Promise<XlsxViewport> {
    return xlsxViewport(
      await this.connection.request({ operation: "viewportXlsx", ...options }),
    );
  }
  async hit(layoutId: number, x: number, y: number): Promise<string> {
    const value = await this.connection.request({
      operation: "hitXlsx",
      layoutId,
      x,
      y,
    });
    if (typeof value !== "string" || !/^[A-Z]{1,3}[1-9][0-9]{0,6}$/.test(value))
      throw new Error("Invalid grid hit");
    return value;
  }
  async selectionGeometry(layoutId: number): Promise<XlsxSelectionGeometry> {
    return xlsxSelection(
      await this.connection.request({ operation: "selectionXlsx", layoutId }),
    );
  }
  async fillPreview(
    layoutId: number,
    target: XlsxFillTarget,
  ): Promise<XlsxFillPreview> {
    checkXlsxFillTarget(target);
    return xlsxFillPreview(
      await this.connection.request({
        operation: "fillPreviewXlsx",
        layoutId,
        target,
      }),
    );
  }
  async navigate(
    revision: number,
    direction: "left" | "right" | "up" | "down" | "home",
    extend = false,
  ): Promise<XlsxQuery> {
    return xlsxQuery(
      await this.connection.request({
        operation: "navigateXlsx",
        revision,
        direction,
        extend,
      }),
    );
  }
  async copy(revision: number): Promise<string> {
    const value = await this.connection.request({
      operation: "copyXlsx",
      revision,
    });
    if (typeof value !== "string" || value.length > 1048576)
      throw new Error("Invalid clipboard text");
    return value;
  }
  async paste(
    revision: number,
    text: string,
    acceptWarnings = false,
  ): Promise<XlsxQuery> {
    if (typeof acceptWarnings !== "boolean")
      throw new Error("Invalid validation warning acceptance");
    return xlsxQuery(
      await this.connection.request({
        operation: "pasteXlsx",
        revision,
        text,
        acceptWarnings,
      }),
    );
  }
  async clear(
    revision: number,
    mode: XlsxClearMode = "contents",
  ): Promise<XlsxQuery> {
    return xlsxQuery(
      await this.connection.request({ operation: "clearXlsx", revision, mode }),
    );
  }
  async printLayout(
    revision: number,
    sheet: string,
    options: PrintOptions | null,
    profile: Record<string, string>,
  ): Promise<XlsxPrintLayout> {
    return xlsxPrintLayout(
      await this.connection.request({
        operation: "printXlsx",
        revision,
        sheet,
        options,
        profile,
      }),
    );
  }
  async exportPdf(layoutId: number, outputBytes: number): Promise<Uint8Array> {
    const bytes = await this.connection.request({
      operation: "exportXlsxPdf",
      layoutId,
      outputBytes,
    });
    if (!(bytes instanceof Uint8Array)) throw new Error("Invalid PDF bytes");
    return bytes;
  }
}
