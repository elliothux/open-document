import { Connection } from "./connection.js";
import {
  xlsxQuery,
  checkXlsxSheetEdit,
  type XlsxSheetEdit,
  checkXlsxCellFormat,
  copiedCellFormat,
  type CopiedCellFormat,
  type XlsxCellFormat,
  xlsxViewport,
  xlsxPrintLayout,
  xlsxSelection,
  type XlsxQuery,
  type GridViewport,
  type XlsxViewport,
  type PrintOptions,
  type XlsxPrintLayout,
} from "@open-document/wasm/xlsx";
import type { DrawRect } from "@open-document/wasm/drawing";
import { resourceBudget, type Budget } from "@open-document/wasm/foundation";
export type { XlsxSheetEdit } from "@open-document/wasm/xlsx";
export { xlsxNumberFormats } from "@open-document/wasm/xlsx";
export type {
  XlsxCellFormat,
  XlsxFormatting,
  XlsxCellBorder,
  CopiedCellFormat,
} from "@open-document/wasm/xlsx";

/** Browser workbook transport; one Worker owns the complete core session. */
export class XlsxClient {
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
  async replace(
    revision: number,
    sheet: string,
    range: string,
    values: string[][],
    literal = false,
  ): Promise<XlsxQuery> {
    return xlsxQuery(
      await this.connection.request({
        operation: "replaceXlsx",
        revision,
        sheet,
        range,
        values,
        literal,
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
  async selectionGeometry(layoutId: number): Promise<DrawRect> {
    return xlsxSelection(
      await this.connection.request({ operation: "selectionXlsx", layoutId }),
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
  async paste(revision: number, text: string): Promise<XlsxQuery> {
    return xlsxQuery(
      await this.connection.request({ operation: "pasteXlsx", revision, text }),
    );
  }
  async clear(revision: number): Promise<XlsxQuery> {
    return xlsxQuery(
      await this.connection.request({ operation: "clearXlsx", revision }),
    );
  }
  async printLayout(
    revision: number,
    sheet: string,
    options: PrintOptions,
    profile: Record<string, string>,
  ): Promise<XlsxPrintLayout> {
    return xlsxPrintLayout(
      await this.connection.request({
        operation: "printXlsx",
        revision,
        sheet,
        ...options,
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
