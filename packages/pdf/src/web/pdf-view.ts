import { CommandQueue } from "@open-document/web-core/command-queue";
import { pdfSearchTextUnits } from "@open-document/wasm/engine-source";
import type {
  PdfLayout,
  PdfQuery,
  PdfSelection,
  PdfRangeSelection,
} from "../core/pdf.js";
import type { PdfClient } from "./pdf.js";
import { PdfCanvas } from "./pdf-canvas.js";
import { PdfReading, readingPoint, type ReadingPage } from "./pdf-reading.js";
import { bindPdfKeyboard } from "./pdf-keyboard.js";
import {
  type EditorOutput,
  type EditorSnapshot,
} from "@open-document/web-core/editor-state";
import {
  createPdfEditorState,
  type PdfMatch,
  type PdfEditorData,
  type PdfViewHooks,
} from "./pdf-viewer-state.js";

/** Bounded reading views, with text and geometry supplied by the core. */
export class PdfView {
  readonly element = document.createElement("section");
  readonly viewport = document.createElement("div");
  private singleSurface = new PdfCanvas();
  surface = this.singleSurface;
  private reading: PdfReading | undefined;
  private readingMode: "single" | "continuous" | "double" = "single";
  private rangeSelection: PdfRangeSelection | undefined;
  private anchorPage = "";
  state: PdfQuery;
  layout: PdfLayout | undefined;
  readonly profile: Record<string, string>;
  closing = false;
  closed = false;
  stopped = false;
  scale = 1;
  paused = false;
  readonly observable: ReturnType<typeof createPdfEditorState>;
  errorMessage = "";
  pageDiagnostics: readonly string[] = [];
  private searching = false;
  private searchPage = 0;
  private cleanup: Promise<void> | undefined;
  private zoom = 1;
  private readonly semantics = document.createElement("pre");
  private readonly events = new AbortController();
  private readonly queue = new CommandQueue(
    128,
    () => new Error("PDF input queue exceeds budget"),
  );
  private backgroundPending = 0;
  private searchId = 0;
  private matches: PdfMatch[] = [];
  private searchQuery = "";
  private matchIndex = -1;
  private selection = { anchor: 0, focus: 0 };
  private gesture = 0;
  private anchor = 0;
  private dragging = false;
  private moving = false;
  private latestPoint:
    | {
        x: number;
        y: number;
        gesture: number;
        page?: string;
        layoutId?: number;
      }
    | undefined;

  constructor(
    readonly client: PdfClient,
    state: PdfQuery,
    root: HTMLElement,
    profile: Record<string, string>,
    private readonly hooks: PdfViewHooks = {},
  ) {
    this.state = state;
    this.profile = profile;
    this.observable = createPdfEditorState(state);
    Object.assign(this.element.style, {
      display: "flex",
      flexDirection: "column",
      flex: "1",
      minHeight: "0",
    });
    this.element.setAttribute("aria-label", "PDF document");
    this.viewport.tabIndex = 0;
    this.viewport.setAttribute("role", "group");
    this.viewport.setAttribute(
      "aria-label",
      "PDF page; Page Up and Page Down navigate pages",
    );
    Object.assign(this.viewport.style, {
      position: "relative",
      flex: "1",
      minHeight: "0",
      maxWidth: "100%",
      overflow: "auto",
      touchAction: "none",
    });
    this.viewport.append(this.surface.canvas, this.surface.overlay);
    Object.assign(this.semantics.style, {
      position: "absolute",
      width: "1px",
      height: "1px",
      overflow: "hidden",
      clipPath: "inset(50%)",
      whiteSpace: "pre-wrap",
    });
    this.semantics.setAttribute("aria-label", "PDF page text in content order");
    this.element.append(this.viewport, this.semantics);
    root.append(this.element);
    this.bindInput();
  }

  readonly getSnapshot = (): EditorSnapshot<PdfEditorData> =>
    this.observable.getSnapshot();
  readonly subscribe = (listener: () => void): (() => void) =>
    this.observable.subscribe(listener);
  markSaved(output: EditorOutput): void {
    this.observable.markSaved(output);
  }
  markDownloaded(output: EditorOutput): void {
    this.observable.markDownloaded(output);
  }
  focus(): void {
    if (this.closed || this.closing) throw new Error("Editor is disposed");
    this.viewport.focus({ preventScroll: true });
  }
  async setPaused(paused: boolean): Promise<void> {
    if (this.closed || this.closing) throw new Error("Editor is disposed");
    this.paused = paused;
    this.element.inert = paused;
    if (paused) this.cancelSearch();
    this.hooks.pauseChanged?.();
    this.publish();
    if (paused) await this.queue.whenIdle();
  }
  inputState(): {
    draft: boolean;
    composition: boolean;
    dragging?: boolean;
    property: string;
    propertyReason: string;
    applying: boolean;
  } {
    return {
      draft: false,
      composition: false,
      property: "",
      propertyReason: "",
      applying: false,
    };
  }
  publish(): void {
    const input = this.hooks.inputState?.() ?? this.inputState();
    const old = this.observable.getSnapshot().data;
    const data =
      old.query === this.state &&
      old.readingMode === this.readingMode &&
      old.matches === this.matches &&
      old.searchQuery === this.searchQuery &&
      old.matchIndex === this.matchIndex &&
      old.searching === this.searching &&
      old.searchPage === this.searchPage &&
      old.property === input.property &&
      old.propertyReason === input.propertyReason &&
      old.applying === input.applying
        ? old
        : {
            readingMode: this.readingMode,
            query: this.state,
            matches: this.matches,
            searchQuery: this.searchQuery,
            matchIndex: this.matchIndex,
            searching: this.searching,
            searchPage: this.searchPage,
            property: input.property,
            propertyReason: input.propertyReason,
            applying: input.applying,
          };
    this.observable.update({
      revision: this.state.revision,
      canUndo: this.state.canUndo && !input.draft && !input.applying,
      canRedo: this.state.canRedo && !input.draft && !input.applying,
      page: this.state.pages.findIndex((page) => page.id === this.state.page),
      pageCount: this.state.pages.length,
      zoom: this.zoom,
      selection: this.rangeSelection
        ? "pages"
        : this.selection.anchor === this.selection.focus
          ? ""
          : `${this.selection.anchor}:${this.selection.focus}`,
      composition: input.composition,
      dragging: this.dragging || input.dragging === true,
      draft: input.draft,
      busy: Math.max(
        this.queue.pending - this.backgroundPending,
        input.applying ? 1 : 0,
      ),
      paused: this.paused,
      stopped: this.stopped,
      closed: this.closed,
      error: this.errorMessage,
      readOnlyReason: this.state.readOnlyReason,
      diagnostics: this.pageDiagnostics,
      data,
    });
  }

  get snapshot(): Readonly<PdfQuery> {
    return this.state;
  }
  get displayedPage(): Readonly<PdfLayout> | undefined {
    return this.layout;
  }

  perform(action: () => Promise<unknown>): void {
    void action().catch((error) => {
      if (!this.closed && !this.closing) {
        this.errorMessage =
          error instanceof Error ? error.message : String(error);
        this.publish();
      }
    });
  }
  enqueue<T>(
    action: () => Promise<T>,
    output = false,
    background = false,
  ): Promise<T> {
    if (this.closed || this.closing)
      return Promise.reject(new Error("PDF viewer is closed"));
    if (this.paused && !output)
      return Promise.reject(new Error("Editor input is paused"));
    return this.queue.enqueue(
      action,
      () => {
        if (background) this.backgroundPending++;
        this.publish();
        this.element.setAttribute(
          "aria-busy",
          String(this.queue.pending > this.backgroundPending),
        );
      },
      (result) => {
        if (!background && result.status === "rejected") {
          const error: unknown = result.reason;
          this.errorMessage =
            error instanceof Error ? error.message : String(error);
        }
        if (background) this.backgroundPending--;
        this.publish();
        if (!this.closed)
          this.element.setAttribute(
            "aria-busy",
            String(this.queue.pending > this.backgroundPending),
          );
      },
    );
  }
  checkDraft(): void {
    this.hooks.checkDraft?.();
  }
  checkClose(): void {
    if (this.hooks.checkClose) this.hooks.checkClose();
    else this.checkDraft();
  }
  stateChanged(): void {
    if (this.hooks.stateChanged) this.hooks.stateChanged();
    else this.publish();
  }
  retainSearch(): void {
    this.cancelSearch();
    const order = new Map(
      this.state.pages.map((page, index) => [page.id, index]),
    );
    this.matches = this.matches
      .filter((match) => order.has(match.page))
      .sort((left, right) => order.get(left.page)! - order.get(right.page)!);
    this.matchIndex = -1;
  }
  private useReadingPage({ layout, surface, scale }: ReadingPage): void {
    this.layout = layout;
    this.surface = surface;
    this.scale = scale;
    this.state = { ...this.state, page: layout.page };
  }
  private async paintReadingPage(page: ReadingPage): Promise<void> {
    this.useReadingPage(page);
    await this.updateSelection(0, 0);
    this.semantics.textContent = page.layout.text;
    this.pageDiagnostics = page.layout.diagnostics;
    this.stopped = false;
    this.errorMessage = "";
    this.stateChanged();
  }
  async paint(page = this.state.page): Promise<void> {
    this.rangeSelection = undefined;
    this.gesture++;
    this.dragging = false;
    this.latestPoint = undefined;
    this.selection = { anchor: 0, focus: 0 };
    try {
      if (this.reading) {
        await this.paintReadingPage(
          await this.reading.update(this.state, page, this.zoom),
        );
        return;
      }
      const previous = this.layout;
      if (previous && previous.page !== page) {
        await this.client.execute({
          operation: "releasePdfView",
          layoutId: previous.id,
        });
      }
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
      this.pageDiagnostics = [
        ...new Set([...this.state.diagnostics, ...layout.diagnostics]),
      ];
      this.errorMessage = "";
      this.stateChanged();
    } catch (error) {
      this.layout = undefined;
      this.stopped = true;
      if (!this.closed && !this.closing) {
        if (!this.reading)
          this.surface.canvas.width = this.surface.overlay.width = 0;
        this.semantics.textContent = "";
        this.errorMessage =
          "Page presentation stopped. Refresh the page or undo; committed changes remain available for saving.";
      }
      throw error;
    }
  }
  async refresh(): Promise<void> {
    this.checkDraft();
    return this.enqueue(async () => {
      const state = await this.client.execute({ operation: "queryPdf" });
      if (state.revision !== this.state.revision) {
        this.matches = [];
        this.matchIndex = -1;
        this.cancelSearch();
      }
      this.state = state;
      await this.paint();
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
      if (this.reading) {
        this.useReadingPage(
          await this.reading.update(this.state, this.state.page, zoom),
        );
      } else this.scale = this.surface.draw(this.layout, 0, zoom);
      await this.updateSelection();
      this.publish();
    });
  }
  async updateSelection(
    anchor?: number,
    focus?: number,
  ): Promise<PdfSelection> {
    this.rangeSelection = undefined;
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
      if (this.rangeSelection)
        return (
          await this.client.execute({
            operation: "selectedPdfRange",
            revision: this.state.revision,
            profile: this.profile,
          })
        ).text;
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
  async navigation(page?: string) {
    const request = {
      operation: "pdfNavigation",
      ...(page === undefined ? {} : { page }),
    } as const;
    return this.enqueue(() => this.client.execute(request), false, true);
  }
  async setReadingMode(
    mode: "single" | "continuous" | "double",
  ): Promise<void> {
    this.checkDraft();
    if (!["single", "continuous", "double"].includes(mode))
      throw new Error("Unknown PDF reading mode");
    return this.enqueue(async () => {
      if (mode === this.readingMode) return;
      await this.reading?.dispose();
      if (this.readingMode === "single") this.singleSurface.dispose();
      this.reading = undefined;
      this.readingMode = mode;
      if (mode === "single") {
        this.singleSurface = new PdfCanvas();
        this.surface = this.singleSurface;
        this.viewport.replaceChildren(
          this.surface.canvas,
          this.surface.overlay,
        );
      } else {
        this.reading = new PdfReading(
          this.client,
          this.viewport,
          this.profile,
          mode,
          (action) =>
            this.enqueue(async () => {
              const page = await action(
                !this.dragging &&
                  !this.rangeSelection &&
                  this.selection.anchor === this.selection.focus &&
                  !this.hooks.inputState?.().draft,
              );
              if (page && this.layout?.id !== page.layout.id)
                await this.paintReadingPage(page);
            }),
        );
      }
      await this.paint();
    });
  }
  async selectRange(
    anchorPage: string,
    anchor: number,
    focusPage: string,
    focus: number,
  ): Promise<PdfRangeSelection> {
    return this.enqueue(() =>
      this.rangeNow(anchorPage, anchor, focusPage, focus),
    );
  }
  private async rangeNow(
    anchorPage: string,
    anchor: number,
    focusPage: string,
    focus: number,
  ): Promise<PdfRangeSelection> {
    const result = await this.client.execute({
      operation: "selectPdfRange",
      revision: this.state.revision,
      anchorPage,
      anchor,
      focusPage,
      focus,
      profile: this.profile,
    });
    this.rangeSelection = result;
    this.reading?.selection(result.pages);
    this.publish();
    return result;
  }
  cancelSearch(): void {
    this.searchId++;
    this.searching = false;
    this.publish();
  }
  async search(
    query: string,
  ): Promise<{ complete: boolean; matches: PdfMatch[] }> {
    if (!query || query.length > pdfSearchTextUnits)
      throw new Error(
        `Search requires 1 through ${pdfSearchTextUnits} UTF-16 units`,
      );
    const id = ++this.searchId,
      revision = this.state.revision,
      pages = this.state.pages.map((page) => page.id);
    const matches: PdfMatch[] = [];
    this.matches = [];
    this.searchQuery = query;
    this.matchIndex = -1;
    this.searching = true;
    this.searchPage = 0;
    this.publish();
    let complete = true;
    try {
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
          ...result.hits.map((hit) => ({
            page,
            start: hit.start,
            end: hit.end,
          })),
        );
        complete &&= result.complete;
        this.matches = [...matches];
        this.searchPage = index + 1;
        this.publish();
      }
    } finally {
      if (id === this.searchId) {
        this.searching = false;
        this.publish();
      }
    }
    return { complete, matches: [...matches] };
  }
  async nextMatch(delta = 1): Promise<void> {
    return this.navigateMatch(
      () =>
        (this.matchIndex + delta + this.matches.length) % this.matches.length,
      true,
    );
  }
  async showMatch(index: number): Promise<void> {
    return this.navigateMatch(() => index, false);
  }
  private async navigateMatch(
    index: () => number,
    focus: boolean,
  ): Promise<void> {
    this.checkDraft();
    const search = this.searchId;
    return this.enqueue(async () => {
      const target = index();
      const match = this.matches[target];
      if (search !== this.searchId || !match) return;
      this.matchIndex = target;
      if (match.page !== this.state.page) await this.paint(match.page);
      await this.updateSelection(match.start, match.end);
      if (focus) this.viewport.focus();
    });
  }
  private point(event: PointerEvent) {
    return readingPoint(
      this.reading,
      this.layout,
      this.surface,
      this.scale,
      this.gesture,
      event,
    );
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
            layoutId: point.layoutId ?? layout.id,
            x: point.x,
            y: point.y,
          });
          if (
            point.page &&
            (point.page !== this.anchorPage || this.rangeSelection)
          )
            await this.rangeNow(
              this.anchorPage,
              this.anchor,
              point.page,
              hit.offset,
            );
          else await this.updateSelection(this.anchor, hit.offset);
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
        const page = this.reading?.at(event.clientX, event.clientY);
        if (page) this.useReadingPage(page);
        if (
          event.button !== 0 ||
          !this.layout ||
          this.paused ||
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
            this.anchorPage = this.layout.page;
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
    bindPdfKeyboard(
      this,
      signal,
      (action) => this.perform(action),
      (message) => {
        this.errorMessage = message;
        this.publish();
      },
    );
  }
  async close(): Promise<void> {
    if (this.closed) return;
    this.checkClose();
    this.closing = true;
    this.cancelSearch();
    await this.queue.whenIdle();
    try {
      this.checkClose();
    } catch (error) {
      this.closing = false;
      throw error;
    }
    await this.dispose();
  }
  copy(): Promise<void> {
    return this.enqueue(async () => {
      if (this.rangeSelection) {
        const selection = await this.client.execute({
          operation: "selectedPdfRange",
          revision: this.state.revision,
          profile: this.profile,
        });
        await navigator.clipboard.writeText(selection.text);
        return;
      }
      if (!this.layout) throw new Error("PDF page is not displayed");
      const { text } = await this.client.execute({
        operation: "selectedPdfText",
        layoutId: this.layout.id,
      });
      await navigator.clipboard.writeText(text);
    });
  }
  dispose(): Promise<void> {
    if (this.cleanup) return this.cleanup;
    this.closed = true;
    this.closing = true;
    this.cancelSearch();
    this.gesture++;
    this.events.abort();
    this.observable.close();
    this.cleanup = this.queue.whenIdle().finally(async () => {
      await this.reading?.dispose();
      this.singleSurface.dispose();
      this.element.remove();
      this.layout = undefined;
      this.matches = [];
    });
    return this.cleanup;
  }
}
