import { CanvasSurface } from "./canvas-surface.js";
import type { XlsxClient } from "./xlsx.js";
import type { PrintOptions, XlsxPrintLayout } from "@open-document/wasm/xlsx";

/** A bounded page surface for the core's independent print layout. */
export class SpreadsheetPrint {
  readonly element = document.createElement("div");
  private readonly surface = new CanvasSurface();
  private readonly listeners = new AbortController();
  private layout: XlsxPrintLayout | undefined;
  private key = "";
  page = 0;
  get pageCount(): number {
    return this.layout?.regions.length ?? 0;
  }
  get visible(): boolean {
    return !this.element.hidden;
  }

  constructor(private readonly changed: () => void) {
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
    client: XlsxClient,
    revision: number,
    sheet: string,
    options: PrintOptions | null,
    profile: Record<string, string>,
  ): Promise<XlsxPrintLayout> {
    const key = JSON.stringify([revision, sheet, options, profile]);
    if (this.layout && this.key === key) return this.layout;
    const layout = await client.printLayout(revision, sheet, options, profile);
    this.listeners.signal.throwIfAborted();
    this.layout = layout;
    this.key = key;
    return layout;
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
    this.surface.dispose();
    this.element.remove();
  }
}
