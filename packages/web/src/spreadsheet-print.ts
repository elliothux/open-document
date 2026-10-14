import { CanvasSurface } from "./canvas-surface.js";
import type { XlsxClient } from "./xlsx.js";
import type { PrintOptions, XlsxPrintLayout } from "@open-document/wasm/xlsx";

export const defaultPrintOptions: PrintOptions = {
  width: 595.28,
  height: 841.89,
  top: 36,
  right: 36,
  bottom: 36,
  left: 36,
};

/** A bounded page surface for the core's independent print layout. */
export class SpreadsheetPrint {
  readonly element = document.createElement("div");
  private readonly surface = new CanvasSurface();
  private readonly status = document.createElement("p");
  private readonly previous = document.createElement("button");
  private readonly next = document.createElement("button");
  private readonly listeners = new AbortController();
  private layout: XlsxPrintLayout | undefined;
  private key = "";
  private page = 0;

  constructor(onClose: () => void) {
    this.element.hidden = true;
    this.element.setAttribute("role", "region");
    this.element.setAttribute("aria-label", "Spreadsheet print preview");
    this.status.setAttribute("role", "status");
    const close = document.createElement("button");
    close.textContent = "Close print preview";
    this.previous.textContent = "Previous print page";
    this.next.textContent = "Next print page";
    const options = { signal: this.listeners.signal };
    for (const button of [this.previous, this.next, close]) {
      button.type = "button";
      button.addEventListener(
        "pointerdown",
        (event) => event.preventDefault(),
        options,
      );
    }
    this.previous.addEventListener(
      "click",
      () => this.present(this.page - 1),
      options,
    );
    this.next.addEventListener(
      "click",
      () => this.present(this.page + 1),
      options,
    );
    close.addEventListener(
      "click",
      () => {
        this.element.hidden = true;
        onClose();
      },
      options,
    );
    this.element.append(
      this.previous,
      this.next,
      close,
      this.status,
      this.surface.canvas,
    );
  }

  show(layout: XlsxPrintLayout): void {
    this.layout = layout;
    this.element.hidden = false;
    this.present(0);
  }

  async prepare(
    client: XlsxClient,
    revision: number,
    sheet: string,
    options: PrintOptions,
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

  private present(index: number): void {
    if (!this.layout) return;
    this.page = Math.max(0, Math.min(index, this.layout.regions.length - 1));
    this.surface.draw(this.layout, this.page, 0.75);
    this.previous.disabled = this.page === 0;
    this.next.disabled = this.page === this.layout.regions.length - 1;
    this.status.textContent = `Print page ${this.page + 1} of ${this.layout.regions.length}; revision ${this.layout.revision}; 100% print scale`;
  }

  dispose(): void {
    this.listeners.abort();
    this.layout = undefined;
    this.surface.dispose();
    this.element.remove();
  }
}
