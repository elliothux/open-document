import {
  createGridElements,
  gridScrollChanged,
  prepareGridViewport,
  updateGridScroll,
} from "./spreadsheet-elements.js";
import {
  checkSpreadsheetSearch,
  type SpreadsheetSearchResult,
} from "./spreadsheet-search.js";
import {
  xlsxFindOptions,
  type XlsxFindOptions,
} from "@open-document/wasm/xlsx";
export type { SpreadsheetSearchResult } from "./spreadsheet-search.js";
import {
  updateGridSemantics,
  updateGridSelection,
  activeGridCell,
  spreadsheetSnapshotData,
  type SpreadsheetEditorData,
} from "./spreadsheet-semantics.js";
export type { SpreadsheetEditorData } from "./spreadsheet-semantics.js";
import { SpreadsheetPrint } from "./spreadsheet-print.js";
import { CanvasSurface } from "./canvas-surface.js";
import { SpreadsheetFormula } from "./spreadsheet-formula.js";
import {
  spreadsheetKey,
  styleCellDraft,
  paintGridSelection,
  bindCellDraft,
  requireCellCompositionEnd,
  showCellDraft,
} from "./spreadsheet-input.js";
import {
  checkFormatFonts,
  checkCopiedFormatFonts,
  checkFontMapping,
} from "./spreadsheet-format.js";
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
  XlsxSheetEdit,
  XlsxCellFormat,
  CopiedCellFormat,
  XlsxClearMode,
  XlsxSelectionGeometry,
} from "@open-document/wasm/xlsx";

/** One native cell draft; MoonBit owns committed cells, selection and geometry. */
export class SpreadsheetEditor {
  acceptValidationWarnings = false;
  private readonly container: HTMLDivElement;
  private readonly viewport: HTMLDivElement;
  private readonly holder: HTMLDivElement;
  private readonly spacer: HTMLDivElement;
  private readonly input: HTMLTextAreaElement;
  private readonly semantics: HTMLDivElement;
  private readonly surface = new CanvasSurface();
  private readonly printView = new SpreadsheetPrint(() => this.publish());
  private readonly observable: EditorState<SpreadsheetEditorData>;
  private paused = false;
  private blocked = false;
  private errorMessage = "";
  private cleanup: Promise<void> | undefined;
  private readonly listeners = new AbortController();
  private readonly formula: SpreadsheetFormula;
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
    const elements = createGridElements(
      this.root,
      this.surface,
      this.printView,
    );
    this.container = elements.container;
    this.viewport = elements.viewport;
    this.holder = elements.holder;
    this.spacer = elements.spacer;
    this.input = elements.input;
    this.semantics = elements.semantics;
    this.formula = new SpreadsheetFormula(
      this.input,
      this.holder,
      this.listeners.signal,
      () => this.handle(() => this.editFormula()),
    );
    const options = { signal: this.listeners.signal };
    this.viewport.addEventListener(
      "focus",
      () => this.input.focus({ preventScroll: true }),
      options,
    );
    const keydown = (event: KeyboardEvent) =>
      spreadsheetKey(event, {
        rtl: this.state.view.rtl,
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
      });
    this.viewport.addEventListener("keydown", keydown, options);
    this.formula.element.addEventListener("keydown", keydown, options);
    this.viewport.addEventListener(
      "scroll",
      () => {
        if (gridScrollChanged(this.viewport, this.layout, this.scale))
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
    bindCellDraft(this.input, this.listeners.signal, {
      start: () => this.queueDraft(),
      composition: (active) => {
        this.composing = active;
        this.publish();
      },
      changed: () => {
        this.styleInput();
        this.publish();
      },
      blur: () => {
        if (
          !this.formula.switching &&
          (this.draft || this.draftIntent) &&
          !this.composing &&
          !this.committing
        )
          this.handle(() => this.enqueue(() => this.commitDraft()));
      },
      reject: (error) => this.report(error),
    });
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
  /** Mount this stable node beside the grid to expose the shared native draft. */
  get formulaBar(): HTMLElement {
    return this.formula.element;
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
        return await action();
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
  private active() {
    return activeGridCell(this.state, this.layout);
  }
  private editFormula(): Promise<void> {
    return this.enqueue(async () => {
      requireCellCompositionEnd(this.composing);
      if (!this.draft) this.beginDraft(false);
      this.formula.show(true);
      this.styleInput();
    });
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
    showCellDraft(
      this.input,
      () => this.styleInput(),
      retainValue ? undefined : replace ? "" : cell.input,
    );
    this.publish();
  }
  cancelDraft(): void {
    if (this.closed || this.committing || this.composing)
      throw new Error("Finish the accepted edit or composition first");
    this.composing = false;
    this.draft = undefined;
    this.draftIntent = undefined;
    this.formula.show(false);
    this.input.value = "";
    this.errorMessage = "";
    this.styleInput();
    this.publish();
  }
  private async commitDraft(): Promise<void> {
    const draft = this.draft;
    if (!draft) return;
    requireCellCompositionEnd(this.composing);
    this.committing = true;
    this.input.readOnly = true;
    try {
      this.state = await this.client.replace(
        draft.revision,
        draft.sheet,
        draft.address,
        [[this.input.value]],
        false,
        this.acceptValidationWarnings,
      );
      this.draft = undefined;
      this.formula.show(false);
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
    if (this.viewport.hidden) return;
    this.publish();
    try {
      const generation = this.generation;
      const layout = await this.client.viewport({
        ...prepareGridViewport(
          this.viewport,
          this.state.view.rtl,
          this.layout?.scrollX ?? 0,
          this.scale,
        ),
        sheet: this.state.sheet,
        profile: this.profile,
        reveal,
      });
      // Queued commands must reveal their selection despite intervening scroll events.
      if (this.closed || (!reveal && generation !== this.generation)) return;
      this.layout = layout;
      this.scale = this.surface.draw(layout, 0, this.zoomValue);
      updateGridScroll(this.viewport, this.spacer, layout, this.scale);
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
    paintGridSelection(this.surface.clearOverlay(this.scale), rect, layout);
    updateGridSelection(this.semantics, this.active());
    this.styleInput(rect);
  }
  private styleInput(selection?: XlsxSelectionGeometry): void {
    this.formula.prepare();
    styleCellDraft(
      this.input,
      this.draft,
      this.scale,
      this.layout,
      this.viewport.clientWidth,
      selection,
      this.active()?.address,
    );
    this.formula.update(
      !!this.draft || !!this.draftIntent,
      this.active(),
      this.paused || this.blocked || !!this.active()?.readOnlyReason,
    );
  }
  private publish(): void {
    if (!this.observable) return;
    const data = spreadsheetSnapshotData(
      this.state,
      this.printView,
      this.observable.getSnapshot().data,
    );
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
    return this.change(() =>
      this.client.select(this.state.revision, sheet, range),
    );
  }
  find(
    text: string,
    options: XlsxFindOptions = {},
  ): Promise<SpreadsheetSearchResult> {
    return this.enqueue(async () => {
      requireCellCompositionEnd(this.composing);
      await this.commitDraft();
      const sheet = this.state.sheet;
      options = xlsxFindOptions(options);
      return {
        ...(await this.client.find(this.state.revision, sheet, text, options)),
        documentId: this.getSnapshot().documentId,
        sheet,
        text,
        options,
      };
    });
  }
  selectMatch(result: SpreadsheetSearchResult, index: number): Promise<void> {
    return this.change(() => {
      checkSpreadsheetSearch(result, this.getSnapshot(), index);
      const match = result.matches[index]!;
      if (match.hidden)
        throw new Error("Show the worksheet before selecting this match");
      return this.client.select(result.revision, match.sheet, match.address);
    });
  }
  replaceMatches(
    result: SpreadsheetSearchResult,
    replacement: string,
    index?: number,
  ): Promise<void> {
    return this.change(() => {
      checkSpreadsheetSearch(result, this.getSnapshot(), index);
      return this.client.replaceMatches(
        result.revision,
        result.sheet,
        result.text,
        result.options,
        replacement,
        index,
      );
    });
  }
  autoFit(axis: "rows" | "columns"): Promise<void> {
    return this.change(() => {
      const range = this.state.selection.range;
      return this.client.autoFit(
        this.state.revision,
        this.state.sheet,
        axis === "rows" ? range.top : range.left,
        axis === "rows" ? range.bottom : range.right,
        axis,
        this.profile,
      );
    });
  }
  editSheet(change: XlsxSheetEdit, sheet?: string): Promise<void> {
    return this.change(() =>
      this.client.editSheet(
        this.state.revision,
        sheet ?? this.state.sheet,
        change,
      ),
    );
  }
  formatCells(patch: XlsxCellFormat): Promise<void> {
    return this.change(() => {
      checkFormatFonts(patch, this.state.formatting, this.profile);
      return this.client.formatCells(this.state.revision, patch);
    });
  }
  captureFormat(): Promise<CopiedCellFormat> {
    return this.enqueue(async () => {
      requireCellCompositionEnd(this.composing);
      await this.commitDraft();
      return this.client.captureFormat(this.state.revision);
    });
  }
  applyFormat(format: CopiedCellFormat): Promise<void> {
    return this.change(() => {
      checkCopiedFormatFonts(format, this.state.formatting, this.profile);
      return this.client.applyFormat(this.state.revision, format);
    });
  }
  private change(action: () => Promise<XlsxQuery>): Promise<void> {
    return this.enqueue(async () => {
      requireCellCompositionEnd(this.composing);
      await this.commitDraft();
      this.state = await action();
      if (this.printView.visible) {
        this.printView.hide();
        this.viewport.hidden = false;
      }
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
    return this.change(() =>
      this.client.paste(
        this.state.revision,
        text,
        this.acceptValidationWarnings,
      ),
    );
  }
  copy(): Promise<void> {
    return this.enqueue(async () => {
      requireCellCompositionEnd(this.composing);
      await navigator.clipboard.writeText(
        await this.client.copy(this.state.revision),
      );
    });
  }
  private history(redo: boolean): Promise<void> {
    return this.enqueue(async () => {
      requireCellCompositionEnd(this.composing);
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
    return this.output("xlsx", () => this.client.save());
  }
  exportCsv(selection = false): Promise<EditorOutput> {
    return this.output("csv", () =>
      this.client.exportCsv(this.state.revision, selection),
    );
  }
  private output(
    format: EditorOutput["format"],
    bytes: () => Promise<Uint8Array>,
  ): Promise<EditorOutput> {
    return this.enqueue(
      async () => {
        requireCellCompositionEnd(this.composing);
        await this.commitDraft();
        return this.observable.output(
          this.state.revision,
          format,
          await bytes(),
        );
      },
      false,
      true,
    );
  }
  printLayout(options: PrintOptions | null = null): Promise<XlsxPrintLayout> {
    return this.enqueue(async () => {
      requireCellCompositionEnd(this.composing);
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
    options: PrintOptions | null = null,
    outputBytes = 67108864,
  ): Promise<EditorOutput> {
    return this.output("pdf", async () => {
      const layout = await this.printView.prepare(
        this.client,
        this.state.revision,
        this.state.sheet,
        options,
        this.profile,
      );
      return this.client.exportPdf(layout.id, outputBytes);
    });
  }
  clear(mode: XlsxClearMode = "contents"): Promise<void> {
    return this.change(() => {
      if (mode !== "contents") {
        checkFontMapping(this.state.normalFont, this.profile);
      }
      return this.client.clear(this.state.revision, mode);
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
      this.formula.element.remove();
      this.container.remove();
    });
    return this.cleanup;
  }
}
