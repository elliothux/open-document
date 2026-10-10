import { type FoundationClient, OutlineCanvas } from "./foundation";
import type { PageLayout } from "@open-document/wasm/preview";

/** Read-only page host. Font loading and the DOCX session stay with the caller. */
export class DocumentPreview {
  private readonly renderer = new OutlineCanvas();
  private readonly canvas = document.createElement("canvas");
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
    private readonly images: Map<string, ImageBitmap>,
  ) {
    this.attributes = ["tabindex", "role", "aria-label"].map((name) => [
      name,
      root.getAttribute(name),
    ]);
    this.canvas.setAttribute("aria-hidden", "true");
    this.previous.textContent = "Previous page";
    this.next.textContent = "Next page";
    this.status.setAttribute("role", "status");
    const viewport = document.createElement("div");
    viewport.style.overflow = "auto";
    viewport.style.maxHeight = "80vh";
    viewport.append(this.canvas);
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
    const images = new Map<string, ImageBitmap>();
    try {
      signal?.throwIfAborted();
      const flow = await client.flow();
      const paragraphs = [
        ...flow.paragraphs,
        ...flow.tables.flatMap((table) => table.rows.flat(2)),
      ];
      for (const span of paragraphs.flatMap((paragraph) => paragraph.spans)) {
        if (!span.image || images.has(span.image.key)) continue;
        signal?.throwIfAborted();
        const bytes = await client.imageBytes(span.image.key);
        const bitmap = await createImageBitmap(
          new Blob([new Uint8Array(bytes).buffer]),
        );
        images.set(span.image.key, bitmap);
        signal?.throwIfAborted();
        if (
          bitmap.width * bitmap.height > 4194304 ||
          bitmap.width > 4096 ||
          bitmap.height > 4096
        )
          throw new Error("Decoded image exceeds budget");
        const canvas = document.createElement("canvas");
        canvas.width = bitmap.width;
        canvas.height = bitmap.height;
        const context = canvas.getContext("2d");
        if (!context) throw new Error("Canvas is unavailable");
        context.drawImage(bitmap, 0, 0);
        const rgba = context.getImageData(
          0,
          0,
          canvas.width,
          canvas.height,
        ).data;
        canvas.width = canvas.height = 0;
        await client.addImage(
          span.image.key,
          bitmap.width,
          bitmap.height,
          new Uint8Array(rgba),
        );
      }
      signal?.throwIfAborted();
      const layout = await client.layout(profile);
      signal?.throwIfAborted();
      return new DocumentPreview(root, client, layout, images);
    } catch (error) {
      for (const image of images.values()) image.close();
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
    const cssScale = (zoom * 96) / 72;
    const scale = cssScale * window.devicePixelRatio;
    const width = Math.ceil(page.width * scale);
    const height = Math.ceil(page.height * scale);
    if (width * height > 16777216)
      throw new Error("Preview canvas exceeds budget");
    this.canvas.width = width;
    this.canvas.height = height;
    this.canvas.style.width = `${page.width * cssScale}px`;
    this.canvas.style.height = `${page.height * cssScale}px`;
    const context = this.canvas.getContext("2d");
    if (!context) throw new Error("Canvas is unavailable");
    context.scale(scale, scale);
    this.renderer.drawPage(context, this.layout, index, this.images);
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
    this.canvas.width = this.canvas.height = 0;
    this.renderer.dispose();
    for (const image of this.images.values()) image.close();
    this.images.clear();
    this.container.remove();
    for (const [name, value] of this.attributes) {
      if (value === null) this.root.removeAttribute(name);
      else this.root.setAttribute(name, value);
    }
  }
}
