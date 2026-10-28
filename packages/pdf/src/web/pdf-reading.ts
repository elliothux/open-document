import type { PdfLayout, PdfQuery } from "../core/pdf.js";
import type { PdfClient } from "./pdf.js";
import { PdfCanvas } from "./pdf-canvas.js";

export interface ReadingPage {
  layout: PdfLayout;
  surface: PdfCanvas;
  scale: number;
  host: HTMLElement;
}

export function readingPoint(
  reading: PdfReading | undefined,
  layout: PdfLayout | undefined,
  surface: PdfCanvas,
  scale: number,
  gesture: number,
  event: PointerEvent,
) {
  const page = reading?.at(event.clientX, event.clientY);
  const bounds = (page?.surface ?? surface).canvas.getBoundingClientRect();
  const factor = page?.scale ?? scale;
  return {
    x: (event.clientX - bounds.left) / factor,
    y: (event.clientY - bounds.top) / factor,
    gesture,
    page: page?.layout.page ?? layout?.page ?? "",
    layoutId: page?.layout.id ?? layout?.id ?? 0,
  };
}

/** Visible page canvases share the existing renderer and bounded core views. */
export class PdfReading {
  private state: PdfQuery | undefined;
  private zoom = 1;
  private readonly hosts = new Map<string, HTMLElement>();
  private readonly rendered = new Map<string, ReadingPage>();
  private pending = false;
  private disposed = false;
  private readonly events = new AbortController();

  constructor(
    private readonly client: PdfClient,
    private readonly viewport: HTMLElement,
    private readonly profile: Record<string, string>,
    private readonly mode: "continuous" | "double",
    private readonly request: (action: () => Promise<void>) => Promise<void>,
  ) {
    viewport.addEventListener("scroll", () => this.schedule(), {
      signal: this.events.signal,
    });
  }

  private schedule(): void {
    if (this.pending || this.disposed || !this.state) return;
    this.pending = true;
    requestAnimationFrame(() => {
      void this.request(async () => {
        if (this.state && !this.disposed)
          await this.update(this.state, this.state.page, this.zoom, false);
      })
        .finally(() => {
          this.pending = false;
        })
        .catch(() => {});
    });
  }

  private async clear(): Promise<void> {
    for (const page of this.rendered.values()) {
      page.surface.dispose();
      await this.client.execute({
        operation: "releasePdfView",
        layoutId: page.layout.id,
      });
    }
    this.rendered.clear();
    this.hosts.clear();
    this.viewport.replaceChildren();
  }

  async update(
    state: PdfQuery,
    active: string,
    zoom: number,
    navigate = true,
  ): Promise<ReadingPage> {
    if (this.disposed) throw new Error("PDF reading view is disposed");
    if (this.state?.revision !== state.revision || this.zoom !== zoom) {
      await this.clear();
      this.state = state;
      this.zoom = zoom;
      const content = document.createElement("div");
      Object.assign(content.style, {
        display: "grid",
        gridTemplateColumns:
          this.mode === "double" ? "max-content max-content" : "max-content",
        gap: "16px",
        padding: "8px",
        alignItems: "start",
      });
      for (const [index, page] of state.pages.entries()) {
        const host = document.createElement("section");
        host.dataset.pdfPage = page.id;
        host.setAttribute("aria-label", `PDF page ${index + 1}`);
        Object.assign(host.style, {
          position: "relative",
          width: `${(page.width * zoom * 96) / 72}px`,
          height: `${(page.height * zoom * 96) / 72}px`,
          background: "white",
          boxShadow: "0 1px 4px #0003",
        });
        this.hosts.set(page.id, host);
        content.append(host);
      }
      this.viewport.append(content);
    }
    this.state = { ...state, page: active };
    if (navigate)
      this.hosts
        .get(active)
        ?.scrollIntoView({ block: "nearest", inline: "nearest" });
    const bounds = this.viewport.getBoundingClientRect();
    const visible = state.pages
      .filter((page) => {
        const rect = this.hosts.get(page.id)!.getBoundingClientRect();
        return (
          rect.bottom > bounds.top &&
          rect.top < bounds.bottom &&
          rect.right > bounds.left &&
          rect.left < bounds.right
        );
      })
      .slice(0, 6);
    const keep = new Set([active, ...visible.map((page) => page.id)]);
    const last = visible.at(-1);
    const neighbor = last
      ? state.pages[state.pages.findIndex((page) => page.id === last.id) + 1]
      : undefined;
    if (neighbor && keep.size < 8) keep.add(neighbor.id);
    for (const [id, page] of this.rendered) {
      if (keep.has(id)) continue;
      page.surface.dispose();
      page.host.replaceChildren();
      this.rendered.delete(id);
      await this.client.execute({
        operation: "releasePdfView",
        layoutId: page.layout.id,
      });
    }
    for (const id of keep) {
      if (this.rendered.has(id)) continue;
      const layout = await this.client.execute({
        operation: "renderPdfPage",
        revision: state.revision,
        page: id,
        profile: this.profile,
        activate: false,
      });
      const surface = new PdfCanvas();
      const host = this.hosts.get(id)!;
      try {
        await surface.prepare(this.client, layout);
        host.append(surface.canvas, surface.overlay);
        const scale = surface.draw(layout, 0, zoom);
        const retained = [...this.rendered.values()].reduce(
          (bytes, item) =>
            bytes + item.surface.canvas.width * item.surface.canvas.height * 8,
          surface.canvas.width * surface.canvas.height * 8,
        );
        if (retained > 67108864)
          throw new Error("PDF page canvases exceed the 64 MiB reading budget");
        this.rendered.set(id, { layout, surface, scale, host });
      } catch (error) {
        surface.dispose();
        host.replaceChildren();
        await this.client.execute({
          operation: "releasePdfView",
          layoutId: layout.id,
        });
        throw error;
      }
    }
    const page = this.rendered.get(active);
    if (!page) throw new Error("Active PDF page is unavailable");
    return page;
  }

  at(x: number, y: number): ReadingPage | undefined {
    return [...this.rendered.values()].find((page) => {
      const box = page.host.getBoundingClientRect();
      return x >= box.left && x <= box.right && y >= box.top && y <= box.bottom;
    });
  }

  get(page: string): ReadingPage | undefined {
    return this.rendered.get(page);
  }

  selection(pages: { page: string; quads: number[][] }[]): void {
    for (const [id, page] of this.rendered)
      page.surface.selection(
        pages.find((item) => item.page === id)?.quads ?? [],
        page.scale,
      );
  }

  async dispose(): Promise<void> {
    this.disposed = true;
    this.events.abort();
    await this.clear();
  }
}
