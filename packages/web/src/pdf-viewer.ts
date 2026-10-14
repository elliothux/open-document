import type {
  PdfBudget,
  PdfLayout,
  PdfQuery,
  PdfSelection,
} from "@open-document/wasm/pdf";
import { PdfClient } from "./pdf.js";
import { PdfCanvas } from "./pdf-canvas.js";
import { bindClipboard } from "./clipboard-input.js";

export interface PdfViewerOptions {
  container: HTMLElement;
  wasm: ArrayBuffer;
  workerUrl: URL;
  bytes: Uint8Array;
  budget?: PdfBudget;
  fonts?: { bytes: Uint8Array; identity: string }[];
  profile?: Record<string, string>;
}
export interface PdfMatch {
  page: string;
  start: number;
  end: number;
}

/** A single visible page, with text and geometry supplied by the core. */
export class PdfViewer {
  readonly element = document.createElement("section");
  readonly viewport = document.createElement("div");
  protected readonly toolbar = document.createElement("div");
  protected readonly status = document.createElement("p");
  protected readonly surface = new PdfCanvas();
  protected state: PdfQuery;
  protected layout: PdfLayout | undefined;
  protected readonly profile: Record<string, string>;
  protected closing = false;
  protected closed = false;
  protected stopped = false;
  protected scale = 1;
  private zoom = 1;
  private readonly pageSelect = document.createElement("select");
  private readonly semantics = document.createElement("pre");
  private readonly diagnostics = document.createElement("ul");
  private readonly events = new AbortController();
  private tail: Promise<unknown> = Promise.resolve();
  private pending = 0;
  private searchId = 0;
  private matches: PdfMatch[] = [];
  private matchIndex = -1;
  private selection = { anchor: 0, focus: 0 };
  private gesture = 0;
  private anchor = 0;
  private dragging = false;
  private moving = false;
  private latestPoint: { x: number; y: number; gesture: number } | undefined;

  protected constructor(
    protected readonly client: PdfClient,
    state: PdfQuery,
    options: PdfViewerOptions,
  ) {
    this.state = state;
    this.profile = options.profile ?? {};
    this.element.setAttribute("aria-label", "PDF document");
    this.toolbar.setAttribute("role", "toolbar");
    this.toolbar.setAttribute("aria-label", "PDF navigation and search");
    this.status.setAttribute("role", "status");
    this.status.setAttribute("aria-live", "polite");
    this.viewport.tabIndex = 0;
    this.viewport.setAttribute("role", "group");
    this.viewport.setAttribute(
      "aria-label",
      "PDF page; Page Up and Page Down navigate pages",
    );
    Object.assign(this.viewport.style, {
      position: "relative",
      width: "fit-content",
      maxWidth: "100%",
      overflow: "auto",
      touchAction: "none",
    });
    this.viewport.append(this.surface.canvas, this.surface.overlay);
    this.pageSelect.setAttribute("aria-label", "PDF page");
    this.pageSelect.addEventListener(
      "change",
      () => this.perform(() => this.goToPage(this.pageSelect.value)),
      { signal: this.events.signal },
    );
    const zoom = document.createElement("select");
    zoom.setAttribute("aria-label", "PDF zoom");
    for (const value of [0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4])
      zoom.add(
        new Option(`${value * 100}%`, String(value), value === 1, value === 1),
      );
    zoom.addEventListener(
      "change",
      () => this.perform(() => this.setZoom(Number(zoom.value))),
      { signal: this.events.signal },
    );
    const search = document.createElement("input");
    search.type = "search";
    search.maxLength = 1024;
    search.setAttribute("aria-label", "Find in PDF");
    search.addEventListener(
      "keydown",
      (event) => {
        if (event.key === "Enter" && !event.isComposing) {
          event.preventDefault();
          this.perform(() => this.search(search.value));
        }
      },
      { signal: this.events.signal },
    );
    this.toolbar.append(
      this.button("Previous page", () => this.navigatePage(-1)),
      this.pageSelect,
      this.button("Next page", () => this.navigatePage(1)),
      zoom,
      search,
      this.button("Find", () => this.search(search.value)),
      this.button("Cancel search", async () => {
        this.cancelSearch();
        this.status.textContent = "Search cancelled";
      }),
      this.button("Previous result", () => this.nextMatch(-1)),
      this.button("Next result", () => this.nextMatch(1)),
      this.button("Refresh page", () => this.refresh()),
    );
    Object.assign(this.semantics.style, {
      position: "absolute",
      width: "1px",
      height: "1px",
      overflow: "hidden",
      clipPath: "inset(50%)",
      whiteSpace: "pre-wrap",
    });
    this.semantics.setAttribute("aria-label", "PDF page text in content order");
    this.diagnostics.setAttribute("aria-label", "PDF diagnostics");
    this.element.append(
      this.toolbar,
      this.status,
      this.viewport,
      this.semantics,
      this.diagnostics,
    );
    options.container.append(this.element);
    this.bindInput();
  }

  protected static async connect(
    options: PdfViewerOptions,
  ): Promise<{ client: PdfClient; state: PdfQuery }> {
    const client = await PdfClient.open(options.wasm, options.workerUrl);
    try {
      for (const font of options.fonts ?? [])
        await client.addFont(font.bytes, font.identity);
      const state = await client.execute({
        operation: "openPdf",
        bytes: options.bytes,
        budget: options.budget ?? (await client.defaultBudget()),
      });
      return { client, state };
    } catch (error) {
      client.dispose();
      throw error;
    }
  }
  static async create(options: PdfViewerOptions): Promise<PdfViewer> {
    const { client, state } = await this.connect(options);
    const viewer = new PdfViewer(client, state, options);
    try {
      await viewer.refresh();
      return viewer;
    } catch (error) {
      viewer.dispose();
      throw error;
    }
  }
  get snapshot(): Readonly<PdfQuery> {
    return this.state;
  }
  get displayedPage(): Readonly<PdfLayout> | undefined {
    return this.layout;
  }

  protected button(
    label: string,
    action: () => Promise<unknown>,
  ): HTMLButtonElement {
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = label;
    button.addEventListener("click", () => this.perform(action), {
      signal: this.events.signal,
    });
    return button;
  }
  protected perform(action: () => Promise<unknown>): void {
    void action().catch((error) => {
      if (!this.closed && !this.closing) {
        this.pageSelect.value = this.state.page;
        this.status.textContent =
          error instanceof Error ? error.message : String(error);
      }
    });
  }
  protected enqueue<T>(action: () => Promise<T>): Promise<T> {
    if (this.closed || this.closing)
      return Promise.reject(new Error("PDF viewer is closed"));
    if (this.pending >= 128)
      return Promise.reject(new Error("PDF input queue exceeds budget"));
    this.pending++;
    this.element.setAttribute("aria-busy", "true");
    const result = this.tail.then(action);
    this.tail = result
      .catch(() => {})
      .finally(() => {
        this.pending--;
        if (!this.closed)
          this.element.setAttribute("aria-busy", String(this.pending > 0));
      });
    return result;
  }
  protected checkDraft(): void {}
  protected checkClose(): void {
    this.checkDraft();
  }
  protected stateChanged(): void {}
  protected retainSearch(): void {
    this.cancelSearch();
    const order = new Map(
      this.state.pages.map((page, index) => [page.id, index]),
    );
    this.matches = this.matches
      .filter((match) => order.has(match.page))
      .sort((left, right) => order.get(left.page)! - order.get(right.page)!);
    this.matchIndex = -1;
  }
  protected async paint(page = this.state.page): Promise<void> {
    this.gesture++;
    this.dragging = false;
    this.latestPoint = undefined;
    this.selection = { anchor: 0, focus: 0 };
    try {
      const layout = await this.client.execute({
        operation: "renderPdfPage",
        revision: this.state.revision,
        page,
        profile: this.profile,
      });
      if (this.closing || this.closed) return;
      this.state = { ...this.state, page: layout.page };
      this.layout = layout;
      await this.surface.prepare(this.client, layout);
      if (this.closing || this.closed) return;
      this.scale = this.surface.draw(layout, 0, this.zoom);
      this.stopped = false;
      this.semantics.textContent = layout.text;
      this.pageSelect.replaceChildren(
        ...this.state.pages.map(
          (item, index) =>
            new Option(`Page ${index + 1}`, item.id, false, item.id === page),
        ),
      );
      this.diagnostics.replaceChildren(
        ...[...new Set([...this.state.diagnostics, ...layout.diagnostics])].map(
          (message) => {
            const item = document.createElement("li");
            item.textContent = message;
            return item;
          },
        ),
      );
      this.status.textContent = `${layout.displayComplete ? "Page ready" : "Page preview is incomplete"}${layout.textComplete ? "" : "; text extraction is incomplete"}${this.state.modified ? "; unsaved changes" : ""}`;
      this.stateChanged();
    } catch (error) {
      this.layout = undefined;
      this.stopped = true;
      if (!this.closed && !this.closing) {
        this.surface.canvas.width = 0;
        this.surface.clearOverlay(this.scale);
        this.semantics.textContent = "";
        this.status.textContent =
          "Page presentation stopped. Refresh the page or undo; committed changes remain available for saving.";
      }
      throw error;
    }
  }
  async refresh(): Promise<void> {
    this.checkDraft();
    return this.enqueue(() => this.paint());
  }
  async open(bytes: Uint8Array, budget?: PdfBudget): Promise<void> {
    this.checkDraft();
    this.cancelSearch();
    return this.enqueue(async () => {
      const state = await this.client.execute({
        operation: "openPdf",
        bytes,
        budget: budget ?? (await this.client.defaultBudget()),
      });
      this.state = state;
      this.matches = [];
      this.matchIndex = -1;
      if (!this.closing && !this.closed) await this.paint();
    });
  }
  async goToPage(page: string): Promise<void> {
    this.checkDraft();
    return this.enqueue(() => this.paint(page));
  }
  async navigatePage(delta: number): Promise<void> {
    this.checkDraft();
    return this.enqueue(async () => {
      const index = this.state.pages.findIndex(
        (page) => page.id === this.state.page,
      );
      const next =
        this.state.pages[
          Math.max(0, Math.min(this.state.pages.length - 1, index + delta))
        ];
      if (next) await this.paint(next.id);
    });
  }
  async setZoom(zoom: number): Promise<void> {
    if (!Number.isFinite(zoom) || zoom < 0.25 || zoom > 4)
      throw new Error("Invalid PDF zoom");
    return this.enqueue(async () => {
      if (!this.layout) throw new Error("PDF page is not displayed");
      this.zoom = zoom;
      this.scale = this.surface.draw(this.layout, 0, zoom);
      await this.updateSelection();
    });
  }
  protected async updateSelection(
    anchor?: number,
    focus?: number,
  ): Promise<PdfSelection> {
    const layout = this.layout;
    if (!layout) throw new Error("PDF page is not displayed");
    const selection = await this.client.execute({
      operation: "selectPdf",
      layoutId: layout.id,
      anchor: anchor ?? this.selection.anchor,
      focus: focus ?? this.selection.focus,
    });
    if (!this.closed && !this.closing && this.layout?.id === layout.id) {
      this.selection = { anchor: selection.anchor, focus: selection.focus };
      this.surface.selection(selection.quads, this.scale);
    }
    return selection;
  }
  async selectText(anchor: number, focus: number): Promise<PdfSelection> {
    return this.enqueue(() => this.updateSelection(anchor, focus));
  }
  async selectedText(): Promise<string> {
    return this.enqueue(async () => {
      if (!this.layout) throw new Error("PDF page is not displayed");
      return (
        await this.client.execute({
          operation: "selectedPdfText",
          layoutId: this.layout.id,
        })
      ).text;
    });
  }
  async extractText(page = this.state.page) {
    return this.enqueue(() =>
      this.client.execute({
        operation: "extractPdfText",
        revision: this.state.revision,
        page,
        profile: this.profile,
      }),
    );
  }
  cancelSearch(): void {
    this.searchId++;
  }
  async search(
    query: string,
  ): Promise<{ complete: boolean; matches: PdfMatch[] }> {
    if (!query || query.length > 1024)
      throw new Error("Search requires 1 through 1024 UTF-16 units");
    const id = ++this.searchId,
      revision = this.state.revision,
      pages = this.state.pages.map((page) => page.id);
    const matches: PdfMatch[] = [];
    this.matches = matches;
    this.matchIndex = -1;
    let complete = true;
    for (const [index, page] of pages.entries()) {
      if (
        id !== this.searchId ||
        this.closing ||
        this.closed ||
        this.state.revision !== revision
      )
        return { complete: false, matches: [...matches] };
      const result = await this.enqueue(() =>
        this.client.execute({
          operation: "searchPdfPage",
          revision,
          page,
          query,
          profile: this.profile,
        }),
      );
      if (
        id !== this.searchId ||
        this.closing ||
        this.closed ||
        this.state.revision !== revision
      )
        return { complete: false, matches: [...matches] };
      if (matches.length + result.hits.length > 10000)
        throw new Error(
          "Viewer search results exceed 10000; use a narrower query",
        );
      matches.push(
        ...result.hits.map((hit) => ({ page, start: hit.start, end: hit.end })),
      );
      complete &&= result.complete;
      this.status.textContent = `Searched ${index + 1}/${pages.length} pages; ${this.matches.length} results${complete ? "" : "; some text is unavailable"}`;
    }
    return { complete, matches: [...matches] };
  }
  async nextMatch(delta = 1): Promise<void> {
    this.checkDraft();
    return this.enqueue(async () => {
      if (!this.matches.length) return;
      this.matchIndex =
        (this.matchIndex + delta + this.matches.length) % this.matches.length;
      const match = this.matches[this.matchIndex];
      if (!match) return;
      if (match.page !== this.state.page) await this.paint(match.page);
      await this.updateSelection(match.start, match.end);
      this.viewport.focus();
    });
  }
  private point(event: PointerEvent) {
    const bounds = this.surface.canvas.getBoundingClientRect();
    return {
      x: (event.clientX - bounds.left) / this.scale,
      y: (event.clientY - bounds.top) / this.scale,
      gesture: this.gesture,
    };
  }
  private movePointer(): void {
    if (this.moving) return;
    this.moving = true;
    this.perform(() =>
      this.enqueue(async () => {
        while (this.latestPoint) {
          const point = this.latestPoint;
          this.latestPoint = undefined;
          const layout = this.layout;
          if (!layout || point.gesture !== this.gesture) continue;
          const hit = await this.client.execute({
            operation: "hitTestPdf",
            layoutId: layout.id,
            x: point.x,
            y: point.y,
          });
          await this.updateSelection(this.anchor, hit.offset);
        }
      }).finally(() => {
        this.moving = false;
      }),
    );
  }
  private bindInput(): void {
    const signal = this.events.signal;
    this.viewport.addEventListener(
      "pointerdown",
      (event) => {
        if (
          event.button !== 0 ||
          !this.layout ||
          this.stopped ||
          event.target !== this.surface.canvas
        )
          return;
        event.preventDefault();
        this.viewport.focus();
        this.gesture++;
        this.dragging = true;
        this.viewport.setPointerCapture(event.pointerId);
        const point = this.point(event);
        this.perform(() =>
          this.enqueue(async () => {
            if (!this.layout || point.gesture !== this.gesture) return;
            const hit = await this.client.execute({
              operation: "hitTestPdf",
              layoutId: this.layout.id,
              x: point.x,
              y: point.y,
            });
            this.anchor = hit.offset;
            await this.updateSelection(hit.offset, hit.offset);
          }),
        );
      },
      { signal },
    );
    this.viewport.addEventListener(
      "pointermove",
      (event) => {
        if (!this.dragging) return;
        this.latestPoint = this.point(event);
        this.movePointer();
      },
      { signal },
    );
    this.viewport.addEventListener(
      "pointerup",
      (event) => {
        if (!this.dragging) return;
        this.dragging = false;
        this.latestPoint = this.point(event);
        this.movePointer();
        if (this.viewport.hasPointerCapture(event.pointerId))
          this.viewport.releasePointerCapture(event.pointerId);
      },
      { signal },
    );
    this.viewport.addEventListener(
      "pointercancel",
      () => {
        this.dragging = false;
        this.latestPoint = undefined;
        this.gesture++;
      },
      { signal },
    );
    bindClipboard(
      this.viewport,
      signal,
      (cut) =>
        this.perform(async () => {
          if (cut) throw new Error("PDF body text is read-only");
          await navigator.clipboard.writeText(await this.selectedText());
        }),
      () => {
        this.status.textContent = "PDF body text is read-only";
      },
      (error) => {
        this.status.textContent = error.message;
      },
      () => false,
    );
    this.viewport.addEventListener(
      "keydown",
      (event) => {
        if (event.key === "PageDown" || event.key === "PageUp") {
          event.preventDefault();
          this.perform(() =>
            this.navigatePage(event.key === "PageDown" ? 1 : -1),
          );
        } else if (event.key === "F3") {
          event.preventDefault();
          this.perform(() => this.nextMatch(event.shiftKey ? -1 : 1));
        } else if (
          (event.ctrlKey || event.metaKey) &&
          event.key.toLowerCase() === "a" &&
          this.layout
        ) {
          event.preventDefault();
          this.perform(() => this.selectText(0, this.layout?.text.length ?? 0));
        }
      },
      { signal },
    );
  }
  async close(): Promise<void> {
    if (this.closed) return;
    this.checkClose();
    this.closing = true;
    this.cancelSearch();
    await this.tail;
    try {
      this.checkClose();
    } catch (error) {
      this.closing = false;
      throw error;
    }
    this.dispose();
  }
  dispose(): void {
    if (this.closed) return;
    this.closed = true;
    this.closing = true;
    this.cancelSearch();
    this.gesture++;
    this.events.abort();
    this.client.dispose();
    this.surface.dispose();
    this.element.remove();
    this.layout = undefined;
    this.matches = [];
  }
}
