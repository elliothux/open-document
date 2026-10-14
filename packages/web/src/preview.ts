import type { FoundationClient } from "./foundation.js";
import type { PageLayout } from "@open-document/wasm/preview";
import { PageCanvas } from "./page-canvas.js";

/** Read-only page host. Font loading and the DOCX session stay with the caller. */
export class DocumentPreview {
  private readonly text = document.createElement("pre");
  private readonly status = document.createElement("p");
  private readonly previous = document.createElement("button");
  private readonly next = document.createElement("button");
  private readonly container = document.createElement("div");
  private readonly attributes: (readonly [string, string | null])[];
  private page = 0;
  private zoom = 1;
  private closed = false;

  private constructor(
    private readonly root: HTMLElement,
    private readonly client: FoundationClient,
    readonly layout: PageLayout,
    private readonly surface: PageCanvas,
  ) {
    this.attributes = ["tabindex", "role", "aria-label"].map((name) => [
      name,
      root.getAttribute(name),
    ]);
    this.previous.textContent = "Previous page";
    this.next.textContent = "Next page";
    this.status.setAttribute("role", "status");
    const viewport = document.createElement("div");
    viewport.style.overflow = "auto";
    viewport.style.maxHeight = "80vh";
    viewport.append(surface.canvas);
    const semantic = document.createElement("details");
    const summary = document.createElement("summary");
    summary.textContent = "Page text";
    semantic.append(summary, this.text);
    const diagnostics = document.createElement("ul");
    diagnostics.setAttribute("aria-label", "Document diagnostics");
    for (const message of layout.diagnostics) {
      const item = document.createElement("li");
      item.textContent = message;
      diagnostics.append(item);
    }
    this.container.append(
      this.previous,
      this.next,
      this.status,
      viewport,
      semantic,
      diagnostics,
    );
    this.paint();
    root.append(this.container);
    root.tabIndex = 0;
    root.setAttribute("role", "region");
    root.setAttribute("aria-label", "Document preview");
    this.previous.addEventListener("click", this.back);
    this.next.addEventListener("click", this.forward);
    root.addEventListener("keydown", this.key);
  }

  static async create(
    root: HTMLElement,
    client: FoundationClient,
    profile: Record<string, string>,
    signal?: AbortSignal,
  ): Promise<DocumentPreview> {
    const surface = await PageCanvas.create(client, signal);
    try {
      const layout = await client.layout(profile);
      signal?.throwIfAborted();
      return new DocumentPreview(root, client, layout, surface);
    } catch (error) {
      surface.dispose();
      throw error;
    }
  }

  private readonly back = (): void => this.goTo(this.page - 1);
  private readonly forward = (): void => this.goTo(this.page + 1);
  private readonly key = (event: KeyboardEvent): void => {
    if (event.target !== this.root) return;
    if (event.key === "PageDown" || event.key === "ArrowRight") this.forward();
    else if (event.key === "PageUp" || event.key === "ArrowLeft") this.back();
    else if (event.key === "+") this.setZoom(Math.min(4, this.zoom + 0.25));
    else if (event.key === "-") this.setZoom(Math.max(0.25, this.zoom - 0.25));
    else return;
    event.preventDefault();
  };

  goTo(index: number): void {
    if (this.closed) throw new Error("Preview is disposed");
    if (!Number.isInteger(index)) throw new Error("Invalid page index");
    this.paint(
      Math.max(0, Math.min(this.layout.pages.length - 1, index)),
      this.zoom,
    );
  }

  setZoom(zoom: number): void {
    if (this.closed) throw new Error("Preview is disposed");
    if (!Number.isFinite(zoom) || zoom < 0.25 || zoom > 4)
      throw new Error("Invalid zoom");
    this.paint(this.page, zoom);
  }

  private paint(index = this.page, zoom = this.zoom): void {
    const page = this.layout.pages[index];
    if (!page) throw new Error("Unknown page");
    this.surface.draw(this.layout, index, zoom);
    this.page = index;
    this.zoom = zoom;
    this.text.textContent = page.lines
      .map((line) => line.text.replaceAll("\ufffc", "[image]"))
      .join("\n");
    this.status.textContent = `Page ${this.page + 1} of ${this.layout.pages.length}; ${Math.round(this.zoom * 100)}%`;
    this.previous.disabled = this.page === 0;
    this.next.disabled = this.page === this.layout.pages.length - 1;
  }

  /** The core rejects export after another layout or edit replaces this view. */
  async downloadPdf(
    filename = "document.pdf",
    outputBytes = 67108864,
  ): Promise<void> {
    if (this.closed) throw new Error("Preview is disposed");
    const bytes = await this.client.exportPdf(outputBytes, this.layout.id);
    if (this.closed) throw new Error("Preview is disposed");
    const url = URL.createObjectURL(
      new Blob([new Uint8Array(bytes).buffer], { type: "application/pdf" }),
    );
    const link = document.createElement("a");
    try {
      link.href = url;
      link.download = filename;
      link.click();
    } finally {
      URL.revokeObjectURL(url);
    }
  }

  dispose(): void {
    if (this.closed) return;
    this.closed = true;
    this.root.removeEventListener("keydown", this.key);
    this.previous.removeEventListener("click", this.back);
    this.next.removeEventListener("click", this.forward);
    this.surface.dispose();
    this.container.remove();
    for (const [name, value] of this.attributes) {
      if (value === null) this.root.removeAttribute(name);
      else this.root.setAttribute(name, value);
    }
  }
}
