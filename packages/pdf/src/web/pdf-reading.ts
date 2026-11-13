import { DocumentError } from "@open-document/wasm/abi/session";
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
  private dpr = 0;
  private readonly hosts = new Map<string, HTMLElement>();
  private readonly rendered = new Map<string, ReadingPage>();
  private readonly limited = new Set<string>();
  private pending = false;
  private disposed = false;
  private readonly events = new AbortController();

  constructor(
    private readonly client: PdfClient,
    private readonly viewport: HTMLElement,
    private readonly profile: Record<string, string>,
    private readonly mode: "continuous" | "double",
    private readonly request: (
      action: (canSwitchPage: boolean) => Promise<ReadingPage | undefined>,
    ) => Promise<void>,
  ) {
    viewport.addEventListener("scroll", () => this.schedule(), {
      signal: this.events.signal,
    });
  }

  private schedule(): void {
    if (this.pending || this.disposed || !this.state) return;
    this.pending = true;
    requestAnimationFrame(() => {
      const scrollPosition = () =>
        `${this.viewport.scrollTop}:${this.viewport.scrollLeft}`;
      let position = scrollPosition();
      void this.request(async (canSwitchPage) => {
        position = scrollPosition();
        if (this.state && !this.disposed)
          return this.update(
            this.state,
            this.state.page,
            this.zoom,
            false,
            canSwitchPage,
          );
      })
        .finally(() => {
          this.pending = false;
          if (position !== scrollPosition()) this.schedule();
        })
        .catch(() => {});
    });
  }

  private async release(id: string, page: ReadingPage): Promise<void> {
    page.surface.dispose();
    page.host.replaceChildren();
    this.rendered.delete(id);
    await this.client.execute({
      operation: "releasePdfView",
      layoutId: page.layout.id,
    });
  }

  private async clear(): Promise<void> {
    for (const [id, page] of this.rendered) await this.release(id, page);
    this.hosts.clear();
    this.limited.clear();
    this.viewport.replaceChildren();
  }

  private visiblePages(pages: PdfQuery["pages"]): number[] {
    const bounds = this.viewport.getBoundingClientRect();
    const columns = this.mode === "double" ? 2 : 1;
    const rect = (index: number) =>
      this.hosts.get(pages[index]!.id)!.getBoundingClientRect();
    let start = 0,
      end = Math.ceil(pages.length / columns);
    // Grid rows have increasing bottom edges, even when the two pages differ in height.
    while (start < end) {
      const middle = Math.floor((start + end) / 2),
        index = middle * columns;
      const bottom =
        columns === 2 && index + 1 < pages.length
          ? Math.max(rect(index).bottom, rect(index + 1).bottom)
          : rect(index).bottom;
      if (bottom <= bounds.top) start = middle + 1;
      else end = middle;
    }
    const visible: number[] = [];
    for (
      let index = start * columns;
      index < pages.length && visible.length < 6;
      index++
    ) {
      const page = rect(index);
      if (page.top >= bounds.bottom) break;
      if (
        page.bottom > bounds.top &&
        page.right > bounds.left &&
        page.left < bounds.right
      )
        visible.push(index);
    }
    return visible;
  }

  async update(
    state: PdfQuery,
    active: string,
    zoom: number,
    navigate = true,
    canSwitchPage = false,
  ): Promise<ReadingPage> {
    if (this.disposed) throw new Error("PDF reading view is disposed");
    const dpr = window.devicePixelRatio;
    if (
      this.state?.revision !== state.revision ||
      this.zoom !== zoom ||
      this.dpr !== dpr
    ) {
      await this.clear();
      this.state = state;
      this.zoom = zoom;
      this.dpr = dpr;
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
    if (this.state?.page !== active) this.limited.clear();
    this.state = { ...state, page: active };
    if (navigate)
      this.hosts
        .get(active)
        ?.scrollIntoView({ block: "nearest", inline: "nearest" });
    const visible = this.visiblePages(state.pages);
    const visibleIds = new Set(visible.map((index) => state.pages[index]!.id));
    const keep = new Set([active, ...visibleIds]);
    const last = visible.at(-1);
    const neighbor = last === undefined ? undefined : state.pages[last + 1];
    if (neighbor && keep.size < 8) keep.add(neighbor.id);
    const offscreen = [...this.rendered].filter(([id]) => !keep.has(id));
    const spare = Math.min(2, 8 - keep.size);
    // Leave the engine's shared image budget available for incoming pages.
    const cached = new Map(
      spare > 0
        ? offscreen
            .filter(([, page]) => !page.layout.images.length)
            .slice(-spare)
        : [],
    );
    for (const [id, page] of offscreen)
      if (!cached.has(id)) await this.release(id, page);
    for (const id of keep) {
      if (this.rendered.has(id)) continue;
      const promote =
        canSwitchPage && visibleIds.has(id) && !visibleIds.has(active);
      if (id !== active && this.limited.has(id) && !promote) continue;
      const render = () =>
        this.client.execute({
          operation: "renderPdfPage",
          revision: state.revision,
          page: id,
          profile: this.profile,
          activate: false,
          reuse: true,
        });
      let layout: PdfLayout;
      try {
        layout = await render();
      } catch (error) {
        if (
          !(error instanceof DocumentError) ||
          error.code !== "limit-exceeded" ||
          !error.message.startsWith("Release PDF views")
        )
          throw error;
        if (id !== active && !promote) {
          this.limited.add(id);
          continue;
        }
        const images = [...this.rendered].filter(
          ([, page]) => page.layout.images.length,
        );
        if (!images.length) throw error;
        for (const [previous, page] of images)
          await this.release(previous, page);
        layout = await render();
        this.limited.clear();
        active = id;
        this.state = { ...state, page: id };
      }
      const surface = new PdfCanvas();
      const host = this.hosts.get(id)!;
      try {
        await surface.prepare(this.client, layout);
        host.append(surface.canvas, surface.overlay);
        const scale = surface.draw(layout, 0, zoom);
        let retained = [...this.rendered.values()].reduce(
          (bytes, item) =>
            bytes + item.surface.canvas.width * item.surface.canvas.height * 8,
          surface.canvas.width * surface.canvas.height * 8,
        );
        for (const [cachedId, page] of cached) {
          if (retained <= 67108864) break;
          retained -=
            page.surface.canvas.width * page.surface.canvas.height * 8;
          cached.delete(cachedId);
          await this.release(cachedId, page);
        }
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
