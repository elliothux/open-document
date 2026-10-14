import { updateGridSemantics } from "./spreadsheet-semantics.js";
import { downloadBytes } from "./download.js";
import { SpreadsheetPrint, defaultPrintOptions } from "./spreadsheet-print.js";
import { CanvasSurface } from "./canvas-surface.js";
import { bindClipboard } from "./clipboard-input.js";
import type { XlsxClient } from "./xlsx.js";
import type {
  XlsxQuery,
  XlsxViewport,
  XlsxPrintLayout,
  PrintOptions,
} from "@open-document/wasm/xlsx";

/** One native cell draft; MoonBit owns committed cells, selection and geometry. */
export class SpreadsheetEditor {
  private readonly container = document.createElement("div");
  private readonly viewport = document.createElement("div");
  private readonly holder = document.createElement("div");
  private readonly spacer = document.createElement("div");
  private readonly input = document.createElement("textarea");
  private readonly semantics = document.createElement("div");
  private readonly sheet = document.createElement("select");
  private readonly zoom = document.createElement("select");
  private readonly status = document.createElement("p");
  private readonly error = document.createElement("p");
  private readonly undoButton = document.createElement("button");
  private readonly redoButton = document.createElement("button");
  private readonly surface = new CanvasSurface();
  private readonly printView = new SpreadsheetPrint(() =>
    this.input.focus({ preventScroll: true }),
  );
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
    this.container.setAttribute("role", "region");
    this.container.setAttribute("aria-label", "Spreadsheet editor");
    this.status.setAttribute("role", "status");
    this.error.setAttribute("role", "alert");
    this.sheet.setAttribute("aria-label", "Worksheet");
    this.zoom.setAttribute("aria-label", "Zoom");
    this.viewport.setAttribute("role", "grid");
    this.viewport.setAttribute("aria-label", "Worksheet cells");
    this.viewport.tabIndex = 0;
    Object.assign(this.viewport.style, {
      position: "relative",
      overflow: "auto",
      height: "400px",
      width: "100%",
      border: "1px solid #9ca3af",
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
    const toolbar = document.createElement("div");
    const save = document.createElement("button"),
      print = document.createElement("button"),
      pdf = document.createElement("button"),
      refresh = document.createElement("button");
    this.undoButton.textContent = "Undo";
    this.redoButton.textContent = "Redo";
    save.textContent = "Save XLSX";
    print.textContent = "Print preview";
    pdf.textContent = "Export PDF";
    refresh.textContent = "Refresh";
    toolbar.append(
      this.sheet,
      this.zoom,
      this.undoButton,
      this.redoButton,
      save,
      print,
      pdf,
      refresh,
    );
    for (const value of [0.5, 0.75, 1, 1.25, 1.5, 2]) {
      const option = document.createElement("option");
      option.value = String(value);
      option.textContent = `${value * 100}%`;
      option.selected = value === 1;
      this.zoom.append(option);
    }
    this.container.append(
      toolbar,
      this.status,
      this.error,
      this.viewport,
      this.printView.element,
    );
    this.root.append(this.container);
    const options = { signal: this.listeners.signal };
    const button = (
      element: HTMLButtonElement,
      action: () => Promise<unknown>,
    ) => {
      element.type = "button";
      element.addEventListener(
        "pointerdown",
        (event) => event.preventDefault(),
        options,
      );
      element.addEventListener("click", () => this.handle(action), options);
    };
    button(this.undoButton, () => this.undo());
    button(this.redoButton, () => this.redo());
    button(save, async () =>
      downloadBytes(
        await this.save(),
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "document.xlsx",
      ),
    );
    button(print, () => this.printLayout());
    button(pdf, async () =>
      downloadBytes(await this.exportPdf(), "application/pdf", "document.pdf"),
    );
    button(refresh, () => this.refresh());
    this.sheet.addEventListener(
      "change",
      () => this.handle(() => this.select("A1", this.sheet.value)),
      options,
    );
    this.zoom.addEventListener(
      "change",
      () => this.handle(() => this.setZoom(Number(this.zoom.value))),
      options,
    );
    this.viewport.addEventListener(
      "focus",
      () => this.input.focus({ preventScroll: true }),
      options,
    );
    this.viewport.addEventListener(
      "keydown",
      (event) => this.key(event),
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
      },
      options,
    );
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
        this.handle(() =>
          this.enqueue(async () => {
            this.requireFinished();
            await navigator.clipboard.writeText(
              await this.client.copy(this.state.revision),
            );
          }),
        );
      },
      (text) => this.handle(() => this.paste(text)),
      (error) => this.report(error),
      () => this.composing,
      () => this.draft !== undefined || this.draftIntent !== undefined,
    );
    this.resize = new ResizeObserver(() => this.requestRender());
    this.resize.observe(this.viewport);
    window.addEventListener("resize", () => this.requestRender(), options);
    this.updateControls();
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
      editor.dispose();
      throw error;
    }
  }

  get currentState(): XlsxQuery {
    return this.state;
  }
  get currentLayout(): XlsxViewport | undefined {
    return this.layout;
  }
  whenIdle(): Promise<void> {
    return this.tail;
  }

  private enqueue<T>(action: () => Promise<T>): Promise<T> {
    if (this.closed)
      return Promise.reject(new Error("Spreadsheet editor is disposed"));
    if (this.pending >= 64)
      return Promise.reject(
        new Error("Spreadsheet command queue exceeds budget"),
      );
    this.pending++;
    const task = this.tail.then(async () => {
      if (this.closed) throw new Error("Spreadsheet editor is disposed");
      const result = await action();
      if (this.closed) throw new Error("Spreadsheet editor is disposed");
      return result;
    });
    this.tail = task
      .then(
        () => {},
        () => {},
      )
      .finally(() => {
        this.pending--;
      });
    return task;
  }

  private handle(action: () => Promise<unknown>): void {
    void action().then(
      () => {
        if (!this.closed) this.error.textContent = "";
      },
      (error) => this.report(error),
    );
  }

  private report(error: unknown): void {
    if (!this.closed) {
      this.error.textContent =
        error instanceof Error ? error.message : String(error);
      this.updateControls();
      if (this.draft) this.input.focus({ preventScroll: true });
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
    if (this.closed || this.committing) throw new Error("Cell input is busy");
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
    this.updateControls();
  }

  private cancelDraft(): void {
    this.composing = false;
    this.draft = undefined;
    this.draftIntent = undefined;
    this.input.value = "";
    this.error.textContent = "";
    this.styleInput();
    this.updateControls();
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
      this.input.readOnly = false;
      this.styleInput();
      this.updateControls();
    }
  }

  private key(event: KeyboardEvent): void {
    if (event.isComposing || this.composing) return;
    if (event.key === "Escape") {
      event.preventDefault();
      this.cancelDraft();
      return;
    }
    if (this.draft || this.draftIntent) {
      if ((event.key === "Enter" && !event.shiftKey) || event.key === "Tab") {
        event.preventDefault();
        this.handle(() =>
          this.move(
            event.key === "Tab" ? (event.shiftKey ? "left" : "right") : "down",
          ),
        );
      }
      return;
    }
    const modifier = event.ctrlKey || event.metaKey;
    if (
      modifier &&
      !event.altKey &&
      (event.key.toLowerCase() === "z" || event.key.toLowerCase() === "y")
    ) {
      event.preventDefault();
      this.handle(() =>
        event.shiftKey || event.key.toLowerCase() === "y"
          ? this.redo()
          : this.undo(),
      );
      return;
    }
    const directions: Record<
      string,
      "left" | "right" | "up" | "down" | "home" | undefined
    > = {
      ArrowLeft: "left",
      ArrowRight: "right",
      ArrowUp: "up",
      ArrowDown: "down",
      Home: "home",
      Enter: "down",
      Tab: event.shiftKey ? "left" : "right",
    };
    const direction = directions[event.key];
    if (direction) {
      event.preventDefault();
      this.handle(() =>
        this.move(direction, event.shiftKey && event.key !== "Tab"),
      );
    } else if (event.key === "F2") {
      event.preventDefault();
      this.handle(() => this.enqueue(async () => this.beginDraft(false)));
    } else if (event.key === "Delete" || event.key === "Backspace") {
      event.preventDefault();
      this.handle(() =>
        this.enqueue(async () => {
          this.state = await this.client.clear(this.state.revision);
          await this.present(true);
        }),
      );
    }
  }

  private requestRender(): void {
    if (this.closed) return;
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
    this.updateControls();
    await this.presentSelection();
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
    this.input.style.opacity = this.draft ? "1" : "0";
    this.input.style.pointerEvents = this.draft ? "auto" : "none";
    this.input.style.border = this.draft ? "2px solid #2563eb" : "0";
    if (this.draft) {
      const rect = this.layout?.cells.find(
        (item) => item.cell.address === this.draft?.address,
      )?.rect;
      this.input.style.width = `${Math.max(120, Math.min((rect?.width ?? 90) * this.scale, this.viewport.clientWidth - parseFloat(this.input.style.left)))}px`;
      this.input.style.height = `${Math.max(24, (rect?.height ?? 18) * this.scale)}px`;
    } else {
      this.input.style.width = "1px";
      this.input.style.height = "1px";
    }
  }

  private updateControls(): void {
    this.sheet.replaceChildren();
    for (const sheet of this.state.sheets) {
      if (sheet.state !== "visible") continue;
      const option = document.createElement("option");
      option.value = sheet.id;
      option.textContent = sheet.name;
      this.sheet.append(option);
    }
    this.sheet.value = this.state.sheet;
    this.undoButton.disabled = !this.state.canUndo || !!this.draft;
    this.redoButton.disabled = !this.state.canRedo || !!this.draft;
    const active = this.active();
    const diagnostics = [
      ...this.state.diagnostics,
      ...new Set(
        this.layout?.cells.map((item) => item.diagnostic).filter(Boolean) ?? [],
      ),
    ];
    this.status.textContent = `${this.state.sheets.find((sheet) => sheet.id === this.state.sheet)?.name ?? ""}; ${active?.address ?? ""}; revision ${this.state.revision}; ${Math.round(this.zoomValue * 100)}%${this.draft ? "; editing cell" : ""}${this.state.readOnlyReason ? "; " + this.state.readOnlyReason : ""}${diagnostics.length ? "; " + diagnostics.join("; ") : ""}`;
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
      this.generation++;
      await this.present(true);
      this.input.focus({ preventScroll: true });
    });
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
      this.generation++;
      await this.present(true);
    });
  }
  setZoom(zoom: number): Promise<void> {
    if (!Number.isFinite(zoom) || zoom < 0.25 || zoom > 4)
      return Promise.reject(new Error("Invalid zoom"));
    return this.enqueue(async () => {
      this.zoomValue = zoom;
      this.zoom.value = String(zoom);
      this.scale = (zoom * 96) / 72;
      this.generation++;
      await this.present(true);
    });
  }
  save(): Promise<Uint8Array> {
    return this.enqueue(async () => {
      this.requireFinished();
      await this.commitDraft();
      return this.client.save();
    });
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
      return layout;
    });
  }
  exportPdf(
    options: PrintOptions = defaultPrintOptions,
    outputBytes = 67108864,
  ): Promise<Uint8Array> {
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
      return this.client.exportPdf(layout.id, outputBytes);
    });
  }
  dispose(): void {
    if (this.closed) return;
    this.closed = true;
    this.listeners.abort();
    this.resize.disconnect();
    cancelAnimationFrame(this.frame);
    this.draft = undefined;
    this.surface.dispose();
    this.draftIntent = undefined;
    this.printView.dispose();
    this.container.remove();
  }
}
