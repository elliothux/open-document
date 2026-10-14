import { updateGridSemantics } from "./spreadsheet-semantics.js";
import { SpreadsheetPrint, defaultPrintOptions } from "./spreadsheet-print.js";
import { CanvasSurface } from "./canvas-surface.js";
import { spreadsheetKey, styleCellDraft } from "./spreadsheet-input.js";
import { bindClipboard } from "./clipboard-input.js";
import {
  EditorState,
  type EditorOutput,
  type EditorSnapshot,
} from "./editor-state.js";
import type { XlsxClient } from "./xlsx.js";
import type {
  XlsxQuery,
  XlsxViewport,
  XlsxPrintLayout,
  PrintOptions,
} from "@open-document/wasm/xlsx";

export interface SpreadsheetEditorData {
  readonly query: XlsxQuery;
  readonly printPage: number;
  readonly printPages: number;
  readonly printVisible: boolean;
}

/** One native cell draft; MoonBit owns committed cells, selection and geometry. */
export class SpreadsheetEditor {
  private readonly container = document.createElement("div");
  private readonly viewport = document.createElement("div");
  private readonly holder = document.createElement("div");
  private readonly spacer = document.createElement("div");
  private readonly input = document.createElement("textarea");
  private readonly semantics = document.createElement("div");
  private readonly surface = new CanvasSurface();
  private readonly printView = new SpreadsheetPrint(() => this.publish());
  private readonly observable: EditorState<SpreadsheetEditorData>;
  private paused = false;
  private blocked = false;
  private errorMessage = "";
  private cleanup: Promise<void> | undefined;
  private readonly listeners = new AbortController();
  private readonly resize: ResizeObserver;
  private state: XlsxQuery;
  private layout: XlsxViewport | undefined;
  private scale = 96 / 72;
  private zoomValue = 1;
  private draft:
    { sheet: string; address: string; revision: number } | undefined;
  private draftIntent: object | undefined;
  private composing = false;
  private committing = false;
  private closed = false;
  private tail: Promise<void> = Promise.resolve();
  private pending = 0;
  private frame = 0;
  private generation = 0;
  private rendering = false;

  private constructor(
    private readonly root: HTMLElement,
    private readonly client: XlsxClient,
    private readonly profile: Record<string, string>,
    state: XlsxQuery,
  ) {
    this.state = state;
    this.observable = new EditorState("xlsx", {
      revision: state.revision,
      canUndo: state.canUndo,
      canRedo: state.canRedo,
      readOnlyReason: state.readOnlyReason,
      diagnostics: state.diagnostics,
      data: { query: state, printPage: 0, printPages: 0, printVisible: false },
    });
    Object.assign(this.container.style, {
      display: "flex",
      flexDirection: "column",
      flex: "1",
      minHeight: "0",
    });
    this.container.setAttribute("role", "region");
    this.container.setAttribute("aria-label", "Spreadsheet editor");
    this.viewport.setAttribute("role", "grid");
    this.viewport.setAttribute("aria-label", "Worksheet cells");
    this.viewport.tabIndex = 0;
    Object.assign(this.viewport.style, {
      position: "relative",
      overflow: "auto",
      flex: "1",
      minHeight: "0",
      width: "100%",
    });
    Object.assign(this.holder.style, {
      position: "sticky",
      left: "0",
      top: "0",
      height: "0",
      zIndex: "1",
    });
    Object.assign(this.surface.canvas.style, {
      position: "absolute",
      left: "0",
      top: "0",
    });
    Object.assign(this.input.style, {
      position: "absolute",
      padding: "0",
      border: "0",
      resize: "none",
      font: "14px sans-serif",
      zIndex: "2",
    });
    this.input.tabIndex = -1;
    this.input.autocomplete = "off";
    this.input.spellcheck = false;
    this.input.setAttribute("autocapitalize", "off");
    this.input.setAttribute("aria-label", "Cell input");
    Object.assign(this.semantics.style, {
      position: "absolute",
      top: "0",
      left: "0",
      width: "1px",
      height: "1px",
      overflow: "hidden",
      clipPath: "inset(50%)",
    });
    this.semantics.setAttribute("role", "rowgroup");
    this.holder.append(this.surface.canvas, this.surface.overlay, this.input);
    this.viewport.append(this.holder, this.spacer, this.semantics);
    this.container.append(this.viewport, this.printView.element);
    this.root.append(this.container);
    const options = { signal: this.listeners.signal };
    this.viewport.addEventListener(
      "focus",
      () => this.input.focus({ preventScroll: true }),
      options,
    );
    this.viewport.addEventListener(
      "keydown",
      (event) =>
        spreadsheetKey(event, {
          paused: this.paused,
          composing: this.composing,
          draft: !!this.draft || !!this.draftIntent,
          cancelDraft: () => this.cancelDraft(),
          handle: (action) => this.handle(action),
          move: (direction, extend) => this.move(direction, extend),
          undo: () => this.undo(),
          redo: () => this.redo(),
          edit: () => this.enqueue(async () => this.beginDraft(false)),
          clear: () => this.clear(),
        }),
      options,
    );
    this.viewport.addEventListener(
      "scroll",
      () => {
        if (
          !this.layout ||
          Math.abs(
            this.viewport.scrollLeft / this.scale - this.layout.scrollX,
          ) > 0.1 ||
          Math.abs(this.viewport.scrollTop / this.scale - this.layout.scrollY) >
            0.1
        )
          this.requestRender();
      },
      options,
    );
    this.surface.canvas.addEventListener(
      "pointerdown",
      (event) => {
        if (event.button !== 0) return;
        event.preventDefault();
        const rect = this.surface.canvas.getBoundingClientRect();
        const x = (event.clientX - rect.left) / this.scale,
          y = (event.clientY - rect.top) / this.scale;
        this.handle(() =>
          this.enqueue(async () => {
            await this.commitDraft();
            await this.present();
            if (!this.layout) return;
            const address = await this.client.hit(this.layout.id, x, y);
            this.state = await this.client.select(
              this.state.revision,
              this.state.sheet,
              address,
            );
            await this.presentSelection();
            this.input.focus({ preventScroll: true });
          }),
        );
      },
      options,
    );
    this.surface.canvas.addEventListener(
      "dblclick",
      () => this.handle(() => this.enqueue(async () => this.beginDraft(false))),
      options,
    );
    this.input.addEventListener(
      "beforeinput",
      (event) => {
        if (!this.draft && event.inputType.startsWith("insert")) {
          try {
            this.queueDraft();
          } catch (error) {
            event.preventDefault();
            this.report(error);
          }
        }
      },
      options,
    );
    this.input.addEventListener(
      "compositionstart",
      () => {
        try {
          if (!this.draft) this.queueDraft();
          this.composing = true;
          this.publish();
        } catch (error) {
          this.report(error);
        }
      },
      options,
    );
    this.input.addEventListener(
      "compositionend",
      () => {
        this.composing = false;
        this.publish();
      },
      options,
    );
    this.input.addEventListener("input", () => this.publish(), options);
    this.input.addEventListener(
      "blur",
      () => {
        if (
          (this.draft || this.draftIntent) &&
          !this.composing &&
          !this.committing
        )
          this.handle(() => this.enqueue(() => this.commitDraft()));
      },
      options,
    );
    bindClipboard(
      this.input,
      this.listeners.signal,
      (cut) => {
        if (cut) {
          this.report(new Error("Cut is unsupported; copy or clear cells"));
          return;
        }
        this.handle(() => this.copy());
      },
      (text) => this.handle(() => this.paste(text)),
      (error) => this.report(error),
      () => this.composing,
      () => this.draft !== undefined || this.draftIntent !== undefined,
    );
    this.resize = new ResizeObserver(() => this.requestRender());
    this.resize.observe(this.viewport);
    window.addEventListener("resize", () => this.requestRender(), options);
    this.publish();
    this.styleInput();
  }
  static async mount(
    root: HTMLElement,
    client: XlsxClient,
    profile: Record<string, string>,
  ): Promise<SpreadsheetEditor> {
    const editor = new SpreadsheetEditor(
      root,
      client,
      profile,
      await client.query(),
    );
    try {
      await editor.enqueue(() => editor.present(true));
      return editor;
    } catch (error) {
      await editor.dispose();
      throw error;
    }
  }

  get currentState(): XlsxQuery {
    return this.state;
  }
  get currentLayout(): XlsxViewport | undefined {
    return this.layout;
  }
  readonly getSnapshot = (): EditorSnapshot<SpreadsheetEditorData> =>
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
    if (this.closed) throw new Error("Editor is disposed");
    this.input.focus({ preventScroll: true });
  }
  async setPaused(paused: boolean): Promise<void> {
    if (this.closed) throw new Error("Editor is disposed");
    this.paused = paused;
    this.container.inert = paused;
    this.input.readOnly = paused || this.committing;
    this.publish();
    if (paused) await this.tail;
  }
  whenIdle(): Promise<void> {
    return this.tail;
  }

  private enqueue<T>(
    action: () => Promise<T>,
    recovery = false,
    output = false,
  ): Promise<T> {
    if (this.closed)
      return Promise.reject(new Error("Spreadsheet editor is disposed"));
    if ((this.paused && !output) || (this.blocked && !recovery && !output))
      return Promise.reject(
        new Error(
          this.paused
            ? "Editor input is paused"
            : "Refresh or undo before editing",
        ),
      );
    if (this.pending >= 64)
      return Promise.reject(
        new Error("Spreadsheet command queue exceeds budget"),
      );
    this.pending++;
    this.publish();
    const task = this.tail.then(async () => {
      try {
        const result = await action();
        return result;
      } catch (error) {
        this.report(error);
        throw error;
      }
    });
    this.tail = task
      .then(
        () => {},
        () => {},
      )
      .finally(() => {
        this.pending--;
        this.publish();
      });
    return task;
  }

  private handle(action: () => Promise<unknown>): void {
    void action().then(
      () => {
        if (!this.closed && !this.blocked) {
          this.errorMessage = "";
          this.publish();
        }
      },
      (error) => this.report(error),
    );
  }

  private report(error: unknown): void {
    if (!this.closed) {
      this.errorMessage =
        error instanceof Error ? error.message : String(error);
      this.publish();
      if (this.draft && !this.paused) this.input.focus({ preventScroll: true });
    }
  }

  private requireFinished(): void {
    if (this.composing)
      throw new Error(
        "Cell editing is unfinished: complete or cancel composition first",
      );
  }

  private active() {
    const selection = this.state.selection.range;
    return (
      this.state.cells.find(
        (cell) => cell.row === selection.top && cell.column === selection.left,
      ) ??
      this.layout?.cells.find(
        (item) =>
          item.cell.row === selection.top &&
          item.cell.column === selection.left,
      )?.cell
    );
  }

  private queueDraft(): void {
    if (this.draft || this.draftIntent) return;
    if (this.pending === 0) {
      this.beginDraft(true);
      return;
    }
    const intent = (this.draftIntent = {});
    this.handle(() =>
      this.enqueue(async () => {
        if (this.draftIntent !== intent) return;
        try {
          this.beginDraft(true, true);
        } finally {
          this.draftIntent = undefined;
        }
      }),
    );
  }

  private beginDraft(replace: boolean, retainValue = false): void {
    if (this.closed || this.paused || this.committing)
      throw new Error("Cell input is busy");
    const cell = this.active();
    if (!cell) throw new Error("Select a visible cell first");
    if (cell.readOnlyReason) throw new Error(cell.readOnlyReason);
    this.draft = {
      sheet: this.state.sheet,
      address: cell.address,
      revision: this.state.revision,
    };
    if (!retainValue) this.input.value = replace ? "" : cell.input;
    this.styleInput();
    if (!retainValue) {
      this.input.focus({ preventScroll: true });
      this.input.setSelectionRange(
        this.input.value.length,
        this.input.value.length,
      );
    }
    this.publish();
  }

  cancelDraft(): void {
    if (this.closed || this.committing || this.composing)
      throw new Error("Finish the accepted edit or composition first");
    this.composing = false;
    this.draft = undefined;
    this.draftIntent = undefined;
    this.input.value = "";
    this.errorMessage = "";
    this.styleInput();
    this.publish();
  }

  private async commitDraft(): Promise<void> {
    const draft = this.draft;
    if (!draft) return;
    this.requireFinished();
    this.committing = true;
    this.input.readOnly = true;
    try {
      this.state = await this.client.replace(
        draft.revision,
        draft.sheet,
        draft.address,
        [[this.input.value]],
      );
      this.draft = undefined;
      this.input.value = "";
      this.generation++;
      await this.present(true);
    } finally {
      this.committing = false;
      this.input.readOnly = this.paused;
      this.styleInput();
      this.publish();
    }
  }

  private requestRender(): void {
    if (this.closed || this.paused || this.blocked) return;
    this.generation++;
    if (this.frame || this.rendering) return;
    this.frame = requestAnimationFrame(() => {
      this.frame = 0;
      this.rendering = true;
      const generation = this.generation;
      this.handle(() =>
        this.enqueue(() => this.present()).finally(() => {
          this.rendering = false;
          if (generation !== this.generation) this.requestRender();
        }),
      );
    });
  }

  private async present(reveal = false): Promise<void> {
    this.publish();
    try {
      const generation = this.generation;
      const width = Math.max(120, this.viewport.clientWidth) / this.scale;
      const height = this.viewport.clientHeight / this.scale;
      const layout = await this.client.viewport({
        sheet: this.state.sheet,
        scrollX: this.viewport.scrollLeft / this.scale,
        scrollY: this.viewport.scrollTop / this.scale,
        width,
        height,
        profile: this.profile,
        reveal,
      });
      if (this.closed || generation !== this.generation) return;
      this.layout = layout;
      this.scale = this.surface.draw(layout, 0, this.zoomValue);
      this.spacer.style.width = `${layout.extentWidth * this.scale + 36 * this.scale}px`;
      this.spacer.style.height = `${layout.extentHeight * this.scale + 18 * this.scale}px`;
      this.viewport.scrollLeft = layout.scrollX * this.scale;
      this.viewport.scrollTop = layout.scrollY * this.scale;
      updateGridSemantics(this.semantics, layout.cells);
      this.publish();
      await this.presentSelection();
    } catch (error) {
      this.blocked = true;
      this.report(error);
      throw error;
    }
  }

  private async presentSelection(): Promise<void> {
    const layout = this.layout;
    if (!layout) return;
    const rect = await this.client.selectionGeometry(layout.id);
    if (this.closed || layout !== this.layout) return;
    const context = this.surface.clearOverlay(this.scale);
    context.save();
    context.beginPath();
    context.rect(
      36,
      18,
      layout.regions[0]!.width - 36,
      layout.regions[0]!.height - 18,
    );
    context.clip();
    context.fillStyle = "rgba(37, 99, 235, 0.10)";
    context.fillRect(rect.x, rect.y, rect.width, rect.height);
    context.strokeStyle = "#2563eb";
    context.lineWidth = 1.5;
    context.strokeRect(rect.x, rect.y, rect.width, rect.height);
    context.restore();
    this.input.style.left = `${Math.max(36, rect.x) * this.scale}px`;
    this.input.style.top = `${Math.max(18, rect.y) * this.scale}px`;
    this.styleInput();
    const active = this.active();
    this.input.setAttribute(
      "aria-label",
      `Cell ${active?.address ?? ""} input`,
    );
    this.input.setAttribute(
      "aria-description",
      `${active?.display ?? ""}${active?.readOnlyReason ? "; " + active.readOnlyReason : ""}`,
    );
    for (const cell of this.semantics.querySelectorAll<HTMLElement>(
      "[role=gridcell]",
    ))
      cell.setAttribute(
        "aria-selected",
        String(cell.dataset.address === active?.address),
      );
  }
  private styleInput(): void {
    const rect = this.layout?.cells.find(
      (item) => item.cell.address === this.draft?.address,
    )?.rect;
    styleCellDraft(
      this.input,
      !!this.draft,
      this.scale,
      rect,
      this.viewport.clientWidth,
    );
  }
  private publish(): void {
    if (!this.observable) return;
    const old = this.observable.getSnapshot().data;
    const data =
      old.query === this.state &&
      old.printPage === this.printView.page &&
      old.printPages === this.printView.pageCount &&
      old.printVisible === this.printView.visible
        ? old
        : {
            query: this.state,
            printPage: this.printView.page,
            printPages: this.printView.pageCount,
            printVisible: this.printView.visible,
          };
    this.observable.update({
      revision: this.state.revision,
      canUndo: this.state.canUndo,
      canRedo: this.state.canRedo,
      page: this.printView.visible ? this.printView.page : 0,
      pageCount: this.printView.visible ? this.printView.pageCount : 1,
      zoom: this.zoomValue,
      selection: this.active()?.address ?? "",
      composition: this.composing,
      draft: !!this.draft || !!this.draftIntent,
      busy: this.pending,
      paused: this.paused,
      stopped: this.blocked,
      closed: this.closed,
      error: this.errorMessage,
      readOnlyReason:
        this.state.readOnlyReason || this.active()?.readOnlyReason || "",
      diagnostics: this.state.diagnostics,
      data,
    });
  }
  select(range: string, sheet = this.state.sheet): Promise<void> {
    return this.enqueue(async () => {
      await this.commitDraft();
      this.state = await this.client.select(this.state.revision, sheet, range);
      this.generation++;
      await this.present(true);
      this.input.focus({ preventScroll: true });
    });
  }
  move(
    direction: "left" | "right" | "up" | "down" | "home",
    extend = false,
  ): Promise<void> {
    return this.enqueue(async () => {
      await this.commitDraft();
      this.state = await this.client.navigate(
        this.state.revision,
        direction,
        extend,
      );
      await this.present(true);
      this.input.focus({ preventScroll: true });
    });
  }
  paste(text: string): Promise<void> {
    return this.enqueue(async () => {
      await this.commitDraft();
      this.state = await this.client.paste(this.state.revision, text);
      this.generation++;
      await this.present(true);
      this.input.focus({ preventScroll: true });
    });
  }
  copy(): Promise<void> {
    return this.enqueue(async () => {
      this.requireFinished();
      await navigator.clipboard.writeText(
        await this.client.copy(this.state.revision),
      );
    });
  }
  private history(redo: boolean): Promise<void> {
    return this.enqueue(async () => {
      this.requireFinished();
      if (this.draft)
        throw new Error(
          "Finish or cancel the cell draft before workbook history",
        );
      this.state = redo
        ? await this.client.redo(this.state.revision)
        : await this.client.undo(this.state.revision);
      this.blocked = false;
      this.generation++;
      await this.present(true);
      this.input.focus({ preventScroll: true });
    }, !redo);
  }
  undo(): Promise<void> {
    return this.history(false);
  }
  redo(): Promise<void> {
    return this.history(true);
  }
  refresh(): Promise<void> {
    return this.enqueue(async () => {
      this.state = await this.client.query();
      this.blocked = false;
      this.generation++;
      await this.present(true);
    }, true);
  }
  setZoom(zoom: number): Promise<void> {
    if (!Number.isFinite(zoom) || zoom < 0.25 || zoom > 4)
      return Promise.reject(new Error("Invalid zoom"));
    return this.enqueue(async () => {
      this.zoomValue = zoom;
      this.scale = (zoom * 96) / 72;
      this.generation++;
      await this.present(true);
    });
  }
  save(): Promise<EditorOutput> {
    return this.enqueue(
      async () => {
        this.requireFinished();
        await this.commitDraft();
        return this.observable.output(
          this.state.revision,
          "xlsx",
          await this.client.save(),
        );
      },
      false,
      true,
    );
  }
  printLayout(
    options: PrintOptions = defaultPrintOptions,
  ): Promise<XlsxPrintLayout> {
    return this.enqueue(async () => {
      this.requireFinished();
      await this.commitDraft();
      const layout = await this.printView.prepare(
        this.client,
        this.state.revision,
        this.state.sheet,
        options,
        this.profile,
      );
      this.printView.show(layout);
      this.viewport.hidden = true;
      return layout;
    });
  }
  exportPdf(
    options: PrintOptions = defaultPrintOptions,
    outputBytes = 67108864,
  ): Promise<EditorOutput> {
    return this.enqueue(
      async () => {
        this.requireFinished();
        await this.commitDraft();
        const layout = await this.printView.prepare(
          this.client,
          this.state.revision,
          this.state.sheet,
          options,
          this.profile,
        );
        return this.observable.output(
          this.state.revision,
          "pdf",
          await this.client.exportPdf(layout.id, outputBytes),
        );
      },
      false,
      true,
    );
  }
  clear(): Promise<void> {
    return this.enqueue(async () => {
      this.requireFinished();
      await this.commitDraft();
      this.state = await this.client.clear(this.state.revision);
      this.generation++;
      await this.present(true);
    });
  }
  showPrintPage(index: number): Promise<void> {
    return this.enqueue(async () => this.printView.showPage(index));
  }
  closePrintPreview(): Promise<void> {
    return this.enqueue(async () => {
      this.printView.hide();
      this.viewport.hidden = false;
      this.focus();
    });
  }
  dispose(): Promise<void> {
    if (this.cleanup) return this.cleanup;
    this.closed = true;
    this.container.inert = true;
    this.listeners.abort();
    this.resize.disconnect();
    cancelAnimationFrame(this.frame);
    this.draftIntent = undefined;
    this.observable.close();
    this.cleanup = this.tail.finally(() => {
      this.draft = undefined;
      this.surface.dispose();
      this.printView.dispose();
      this.container.remove();
    });
    return this.cleanup;
  }
}
