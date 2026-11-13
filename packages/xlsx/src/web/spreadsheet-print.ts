import { SpreadsheetCanvas } from "./spreadsheet-canvas.js";
import type { XlsxClient } from "./xlsx.js";
import type { PrintOptions, XlsxPrintLayout, XlsxQuery } from "../core/xlsx.js";

/** A bounded page surface for the core's independent print layout. */
export class SpreadsheetPrint {
  readonly element = document.createElement("div");
  private readonly surface = new SpreadsheetCanvas("print");
  private readonly listeners = new AbortController();
  private layout: XlsxPrintLayout | undefined;
  private prepared: XlsxPrintLayout | undefined;
  private key = "";
  page = 0;
  get pageCount(): number {
    return this.layout?.regions.length ?? 0;
  }
  get visible(): boolean {
    return !this.element.hidden;
  }

  constructor(
    private readonly client: XlsxClient,
    private readonly profile: Record<string, string>,
    private readonly changed: () => void,
  ) {
    this.element.hidden = true;
    this.element.setAttribute("role", "region");
    this.element.setAttribute("aria-label", "Spreadsheet print preview");
    Object.assign(this.element.style, {
      flex: "1",
      minHeight: "0",
      overflow: "auto",
    });
    this.element.append(this.surface.canvas);
  }

  show(layout: XlsxPrintLayout): void {
    this.layout = layout;
    this.element.hidden = false;
    this.showPage(0);
  }
  hide(): void {
    this.element.hidden = true;
    this.changed();
  }

  async prepare(
    state: XlsxQuery,
    options: PrintOptions | null,
  ): Promise<XlsxPrintLayout> {
    const { client, profile } = this;
    const { revision, sheet } = state;
    const key = JSON.stringify([revision, sheet, options, profile]);
    if (this.prepared && this.key === key) return this.prepared;
    const query = await client.execute({ operation: "queryXlsx" });
    const sheets =
      options?.sheets === "visible"
        ? query.sheets
            .filter((sheet) => sheet.state === "visible")
            .map((sheet) => sheet.id)
        : Array.isArray(options?.sheets)
          ? options.sheets
          : [sheet];
    await this.surface.prepare(
      client,
      revision,
      sheets,
      profile,
      this.listeners.signal,
    );
    const layout = await client.execute({
      operation: "printXlsx",
      revision: revision,
      sheet: sheet,
      options: options,
      profile: profile,
    });
    this.listeners.signal.throwIfAborted();
    this.prepared = layout;
    this.key = key;
    return layout;
  }

  async exportPdf(
    state: XlsxQuery,
    options: PrintOptions | null,
    outputBytes: number,
  ): Promise<Uint8Array> {
    const layout = await this.prepare(state, options);
    return this.client.execute({
      operation: "exportXlsxPdf",
      layoutId: layout.id,
      outputBytes,
    });
  }

  showPage(index: number): void {
    if (!this.layout) return;
    this.page = Math.max(0, Math.min(index, this.layout.regions.length - 1));
    this.surface.draw(this.layout, this.page, 0.75);
    this.changed();
  }

  dispose(): void {
    this.listeners.abort();
    this.layout = undefined;
    this.prepared = undefined;
    this.surface.dispose();
    this.element.remove();
  }
}
