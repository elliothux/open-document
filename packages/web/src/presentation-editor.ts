import { updatePresentationObjects } from "./presentation-semantics.js";
import { PresentationCanvas } from "./presentation-canvas.js";
import { PresentationInput } from "./presentation-input.js";
import { PresentationPointer } from "./presentation-pointer.js";
import { bindClipboard } from "./clipboard-input.js";
import {
  EditorState,
  type EditorOutput,
  type EditorSnapshot,
} from "./editor-state.js";
import type { PptxClient } from "./pptx.js";
import type {
  PptxQuery,
  PptxLayout,
  PptxGeometry,
  PptxSelection,
  PptxPoint,
} from "@open-document/wasm/pptx";

/** Embed one slide surface; all document semantics and editable geometry come from MoonBit. */
export class PresentationEditor {
  private readonly container = document.createElement("div");
  private readonly viewport = document.createElement("div");
  private readonly holder = document.createElement("div");
  private readonly input = document.createElement("textarea");
  private readonly semantics = document.createElement("ol");
  private readonly surface = new PresentationCanvas();
  private readonly listeners = new AbortController();
  private readonly observable: EditorState<PptxQuery>;
  private paused = false;
  private errorMessage = "";
  private cleanup: Promise<void> | undefined;
  private readonly inputEvents: PresentationInput;
  private readonly pointer: PresentationPointer;
  private state: PptxQuery;
  private drawing: PptxLayout | undefined;
  private geometry: PptxGeometry | undefined;
  private zoomValue = 1;
  private scale = 96 / 72;
  private tail: Promise<void> = Promise.resolve();
  private pending = 0;
  private closed = false;
  private closing = false;
  private blocked = false;
  private frame = 0;
  private gesture:
    | {
        start: PptxPoint;
        text: boolean;
        anchor: number;
        handle: number;
        token?: { revision: number; id: number };
      }
    | undefined;

  private constructor(
    private readonly root: HTMLElement,
    private readonly client: PptxClient,
    private readonly profile: Record<string, string>,
    state: PptxQuery,
  ) {
    this.state = state;
    this.observable = new EditorState("pptx", {
      revision: state.revision,
      canUndo: state.canUndo,
      canRedo: state.canRedo,
      page: state.slides.findIndex((slide) => slide.id === state.slide),
      pageCount: state.slides.length,
      selection: state.selection.object,
      readOnlyReason: state.readOnlyReason,
      diagnostics: [],
      data: state,
    });
    Object.assign(this.container.style, {
      display: "flex",
      flexDirection: "column",
      flex: "1",
      minHeight: "0",
    });
    this.container.setAttribute("role", "region");
    this.container.setAttribute("aria-label", "Presentation editor");
    this.semantics.setAttribute("aria-label", "Slide objects");
    Object.assign(this.viewport.style, {
      overflow: "auto",
      flex: "1",
      minHeight: "0",
    });
    Object.assign(this.holder.style, {
      position: "relative",
      width: "max-content",
    });
    Object.assign(this.input.style, {
      position: "absolute",
      opacity: "0",
      width: "1px",
      padding: "0",
      border: "0",
      resize: "none",
      pointerEvents: "none",
    });
    this.input.setAttribute("aria-label", "Slide input");
    this.input.autocomplete = "off";
    this.input.spellcheck = false;
    this.input.setAttribute("autocapitalize", "off");
    this.input.tabIndex = -1;
    this.holder.append(this.surface.canvas, this.surface.overlay, this.input);
    this.viewport.append(this.holder);
    this.inputEvents = new PresentationInput(
      this.input,
      this.listeners.signal,
      client,
      {
        state: () => this.state,
        limit: () => 32767,
        available: () =>
          this.available &&
          !this.state.readOnlyReason &&
          this.state.selection.mode === "text",
        enqueue: (operation, composition) =>
          this.enqueue(operation, composition),
        changed: (state, relayout) => this.changed(state, relayout),
        history: async (redo) => {
          await (redo ? this.redo() : this.undo());
        },
        stop: (error) => this.fail(error),
      },
      () => this.layout.id,
      profile,
    );
    this.input.addEventListener("keydown", this.key, {
      signal: this.listeners.signal,
    });
    bindClipboard(
      this.input,
      this.listeners.signal,
      (cut) => this.handle(() => this.copy(cut)),
      (text) => this.handle(() => this.paste(text)),
      (error) => this.fail(error),
      () => this.inputEvents.active,
    );
    this.pointer = new PresentationPointer(
      this.surface.canvas,
      this.listeners.signal,
      {
        available: () =>
          this.available &&
          !this.state.readOnlyReason &&
          !this.inputEvents.active,
        point: (event) => {
          const rect = this.surface.canvas.getBoundingClientRect();
          return {
            x: (event.clientX - rect.left) / this.scale,
            y: (event.clientY - rect.top) / this.scale,
          };
        },
        press: (point, text, extend) => this.press(point, text, extend),
        move: (point) => this.move(point),
        finish: (point, cancel) => this.release(point, cancel),
        fail: (error) => this.fail(error),
      },
    );
    window.addEventListener(
      "resize",
      () => {
        if (
          this.frame ||
          !this.available ||
          this.pointer.active ||
          this.inputEvents.active
        )
          return;
        this.frame = requestAnimationFrame(() => {
          this.frame = 0;
          this.handle(() => this.enqueue(() => this.paint()));
        });
      },
      { signal: this.listeners.signal },
    );
    this.container.append(this.viewport, this.semantics);
    root.append(this.container);
  }
  static async create(
    root: HTMLElement,
    client: PptxClient,
    profile: Record<string, string>,
    signal?: AbortSignal,
  ): Promise<PresentationEditor> {
    signal?.throwIfAborted();
    const editor = new PresentationEditor(
      root,
      client,
      { ...profile },
      await client.execute({ operation: "queryPptx" }),
    );
    try {
      await editor.present();
      signal?.throwIfAborted();
      return editor;
    } catch (error) {
      await editor.dispose();
      throw error;
    }
  }
  private get available(): boolean {
    return !this.closed && !this.closing && !this.paused && !this.blocked;
  }
  get layout(): PptxLayout {
    if (!this.drawing) throw new Error("Presentation layout is unavailable");
    return this.drawing;
  }
  get query(): PptxQuery {
    return structuredClone(this.state);
  }
  readonly getSnapshot = (): EditorSnapshot<PptxQuery> =>
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
    this.input.focus({ preventScroll: true });
  }
  async setPaused(paused: boolean): Promise<void> {
    if (this.closed || this.closing) throw new Error("Editor is disposed");
    this.paused = paused;
    this.container.inert = paused;
    this.input.readOnly = paused || this.blocked;
    this.publish();
    if (paused) await this.tail;
  }
  private publish(): void {
    this.observable.update({
      revision: this.state.revision,
      canUndo: this.state.canUndo,
      canRedo: this.state.canRedo,
      page: this.state.slides.findIndex(
        (slide) => slide.id === this.state.slide,
      ),
      pageCount: this.state.slides.length,
      zoom: this.zoomValue,
      selection: this.state.selection.object,
      composition: this.inputEvents?.active ?? false,
      dragging: !!this.gesture || (this.pointer?.active ?? false),
      busy: this.pending,
      paused: this.paused,
      stopped: this.blocked,
      closed: this.closed,
      error: this.errorMessage,
      readOnlyReason: this.state.readOnlyReason,
      diagnostics: this.drawing?.diagnostics ?? this.state.diagnostics,
      data: this.state,
    });
  }
  private handle(operation: () => Promise<unknown>): void {
    void operation().catch((error) =>
      this.fail(error instanceof Error ? error : new Error(String(error))),
    );
  }
  private fail(error: Error): void {
    if (this.closed) return;
    this.blocked = true;
    this.errorMessage = `${error.message}. Committed edits remain available. Refresh or undo to recover.`;
    this.publish();
  }
  private enqueue<T>(
    operation: () => Promise<T>,
    gesture = false,
    recovery = false,
    output = false,
  ): Promise<T> {
    if (this.closed || this.closing)
      return Promise.reject(new Error("Editor is disposed"));
    if (this.paused && !output)
      return Promise.reject(new Error("Editor input is paused"));
    if (this.blocked && !recovery && !output)
      return Promise.reject(new Error("Refresh or undo before editing"));
    if (
      !gesture &&
      (this.inputEvents.active || this.pointer.active || this.gesture)
    )
      return Promise.reject(
        new Error("Complete or cancel the active gesture first"),
      );
    if (this.pending >= 64)
      return Promise.reject(new Error("Editor queue exceeds budget"));
    this.pending++;
    this.publish();
    const result = this.tail.then(operation);
    this.tail = result.then(
      () => {
        this.pending--;
        this.publish();
      },
      (error) => {
        this.pending--;
        this.fail(error instanceof Error ? error : new Error(String(error)));
      },
    );
    return result;
  }
  private async changed(state: PptxQuery, relayout = false): Promise<void> {
    const content =
      relayout ||
      this.state.revision !== state.revision ||
      this.state.slide !== state.slide;
    this.state = state;
    this.publish();
    if (content) await this.present();
    else {
      this.updateSemantics();
      await this.paintSelection();
    }
  }
  private async present(): Promise<void> {
    await this.surface.prepare(this.client);
    const layout = await this.client.execute({
      operation: "layoutPptx",
      profile: this.profile,
    });
    if (
      layout.revision !== this.state.revision ||
      layout.slide !== this.state.slide
    )
      throw new Error("Slide changed while preparing layout");
    this.drawing = layout;
    this.updateSemantics();
    await this.paint();
  }
  private async paint(): Promise<void> {
    this.scale = this.surface.draw(this.layout, 0, this.zoomValue);
    await this.paintSelection();
  }
  private async paintSelection(): Promise<void> {
    const geometry = await this.client.execute({
      operation: "selectionPptx",
      layoutId: this.layout.id,
    });
    this.geometry = geometry;
    this.surface.drawSelection(geometry, this.scale);
    this.publish();
    const caret = geometry.caret;
    if (caret) {
      this.input.style.left = `${caret.x * this.scale}px`;
      this.input.style.top = `${caret.y * this.scale}px`;
      this.input.style.height = `${caret.height * this.scale}px`;
    }
  }
  private updateSemantics(): void {
    const state = this.state;
    updatePresentationObjects(
      this.semantics,
      state,
      this.listeners.signal,
      (object, mode) => this.handle(() => this.select(object, mode)),
    );
    this.publish();
    this.input.setAttribute(
      "aria-label",
      `${state.selection.mode === "text" ? "Text" : "Object"} input: ${state.objects.find((object) => object.id === state.selection.object)?.name || "slide"}`,
    );
  }
  select(
    object: string,
    mode: "object" | "text" = "object",
    anchor = 0,
    focus = anchor,
  ): Promise<void> {
    return this.enqueue(async () => {
      await this.selectNow({
        slide: this.state.slide,
        object,
        mode,
        anchor,
        focus,
      });
    });
  }
  private async selectNow(selection: PptxSelection): Promise<void> {
    await this.changed(
      await this.client.execute({
        operation: "selectPptx",
        revision: this.state.revision,
        ...selection,
      }),
    );
    this.input.focus({ preventScroll: true });
  }
  showSlide(slide: string): Promise<void> {
    return this.enqueue(async () => {
      await this.cancelNow();
      await this.selectNow({
        slide,
        object: "",
        mode: "object",
        anchor: 0,
        focus: 0,
      });
    }, true);
  }
  setZoom(zoom: number): Promise<void> {
    return this.enqueue(async () => {
      if (!Number.isFinite(zoom) || zoom < 0.25 || zoom > 4)
        throw new Error("Invalid zoom");
      this.zoomValue = zoom;
      await this.paint();
    });
  }
  transform(dx: number, dy: number, handle = 0): Promise<void> {
    return this.enqueue(async () => {
      const state = await this.client.execute({
        operation: "beginPptx",
        revision: this.state.revision,
        kind: "transform",
      });
      if (state.candidateId === null)
        throw new Error("Core did not begin move");
      try {
        await this.client.execute({
          operation: "dragPptx",
          revision: state.revision,
          candidateId: state.candidateId,
          dx,
          dy,
          handle,
        });
        await this.changed(
          await this.client.execute({
            operation: "finishPptx",
            revision: state.revision,
            candidateId: state.candidateId,
            profile: this.profile,
          }),
        );
      } catch (error) {
        await this.cancelNow();
        throw error;
      }
    });
  }
  save(): Promise<EditorOutput> {
    return this.enqueue(
      async () =>
        this.observable.output(
          this.state.revision,
          "pptx",
          await this.client.execute({
            operation: "savePptx",
            revision: this.state.revision,
          }),
        ),
      false,
      false,
      true,
    );
  }
  exportPdf(
    all = true,
    hidden = false,
    outputBytes = 67108864,
  ): Promise<EditorOutput> {
    return this.enqueue(
      async () => {
        try {
          await this.surface.prepare(this.client, all, hidden);
          const revision = this.state.revision;
          const bytes = await this.client.execute({
            operation: "exportPptxPdf",
            revision: this.state.revision,
            all,
            hidden,
            outputBytes,
            profile: this.profile,
          });
          return this.observable.output(revision, "pdf", bytes);
        } finally {
          await this.surface.prepare(this.client);
        }
      },
      false,
      false,
      true,
    );
  }
  private async cancelNow(): Promise<void> {
    this.pointer.reset();
    this.gesture = undefined;
    await this.inputEvents.cancel();
    const state = await this.client.execute({ operation: "queryPptx" });
    this.state =
      state.candidateId === null
        ? state
        : await this.client.execute({
            operation: "cancelPptx",
            revision: state.revision,
            candidateId: state.candidateId,
          });
  }
  undo(): Promise<void> {
    return this.history(false);
  }
  redo(): Promise<void> {
    return this.history(true);
  }
  private history(redo: boolean): Promise<void> {
    return this.enqueue(
      async () => {
        await this.cancelNow();
        this.state = await this.client.execute({
          operation: redo ? "redoPptx" : "undoPptx",
          revision: this.state.revision,
        });
        this.blocked = false;
        this.errorMessage = "";
        await this.present();
      },
      true,
      true,
    );
  }
  refresh(): Promise<void> {
    return this.enqueue(
      async () => {
        await this.cancelNow();
        this.blocked = false;
        this.errorMessage = "";
        await this.present();
      },
      true,
      true,
    );
  }
  copy(cut = false): Promise<void> {
    return this.enqueue(async () => {
      const revision = this.state.revision,
        selection = { ...this.state.selection };
      const { text } = await this.client.execute({
        operation: "copyPptx",
        revision,
      });
      await navigator.clipboard.writeText(text);
      if (cut) {
        const state = await this.client.execute({ operation: "queryPptx" });
        if (
          state.revision !== revision ||
          JSON.stringify(state.selection) !== JSON.stringify(selection)
        )
          throw new Error("Selection changed during clipboard write");
        await this.changed(
          await this.client.execute({
            operation: "replacePptx",
            revision,
            text: "",
            profile: this.profile,
          }),
        );
      }
    });
  }
  paste(text: string): Promise<void> {
    return this.enqueue(async () =>
      this.changed(
        await this.client.execute({
          operation: "replacePptx",
          revision: this.state.revision,
          text: text.replace(/\r\n?/g, "\n"),
          profile: this.profile,
        }),
      ),
    );
  }
  private press(
    point: PptxPoint,
    text: boolean,
    extend: boolean,
  ): Promise<void> {
    return this.enqueue(async () => {
      let handle = 0;
      if (this.state.selection.mode === "object")
        for (const [index, position] of (
          this.geometry?.handles ?? []
        ).entries())
          if (
            Math.hypot(point.x - position.x, point.y - position.y) <=
            6 / this.scale
          )
            handle = index + 1;
      const hit = await this.client.execute({
        operation: "hitPptx",
        layoutId: this.layout.id,
        ...point,
        tolerance: 4 / this.scale,
      });
      const object = handle ? this.state.selection.object : hit.object;
      const mode =
        object &&
        (text ||
          (this.state.selection.mode === "text" &&
            object === this.state.selection.object))
          ? "text"
          : "object";
      const anchor =
        mode === "text" && extend ? this.state.selection.anchor : hit.offset;
      await this.selectNow({
        slide: this.state.slide,
        object,
        mode,
        anchor,
        focus: hit.offset,
      });
      const gesture = { start: point, text: mode === "text", anchor, handle };
      this.gesture = gesture;
    }, true);
  }
  private move(point: PptxPoint): Promise<void> {
    return this.enqueue(async () => {
      const gesture = this.gesture;
      if (!gesture || !this.state.selection.object) return;
      if (gesture.text) {
        const hit = await this.client.execute({
          operation: "hitPptx",
          layoutId: this.layout.id,
          ...point,
          tolerance: 4 / this.scale,
        });
        if (hit.object === this.state.selection.object)
          await this.selectNow({
            ...this.state.selection,
            anchor: gesture.anchor,
            focus: hit.offset,
          });
      } else {
        const dx = point.x - gesture.start.x,
          dy = point.y - gesture.start.y;
        if (!gesture.token && Math.hypot(dx, dy) < 2 / this.scale) return;
        if (!gesture.token) {
          const state = await this.client.execute({
            operation: "beginPptx",
            revision: this.state.revision,
            kind: "transform",
          });
          if (state.candidateId === null)
            throw new Error("Core did not begin drag");
          gesture.token = { revision: state.revision, id: state.candidateId };
          this.state = state;
        }
        await this.changed(
          await this.client.execute({
            operation: "dragPptx",
            revision: gesture.token.revision,
            candidateId: gesture.token.id,
            dx,
            dy,
            handle: gesture.handle,
          }),
          true,
        );
      }
    }, true);
  }
  private async release(point: PptxPoint, cancel: boolean): Promise<void> {
    if (!cancel) await this.move(point);
    await this.enqueue(async () => {
      const gesture = this.gesture;
      this.gesture = undefined;
      if (gesture?.token)
        await this.changed(
          await this.client.execute(
            cancel
              ? {
                  operation: "cancelPptx",
                  revision: gesture.token.revision,
                  candidateId: gesture.token.id,
                }
              : {
                  operation: "finishPptx",
                  revision: gesture.token.revision,
                  candidateId: gesture.token.id,
                  profile: this.profile,
                },
          ),
          true,
        );
    }, true);
  }
  private readonly key = (event: KeyboardEvent): void => {
    if (event.isComposing) return;
    if (event.key === "Escape") {
      event.preventDefault();
      this.handle(() =>
        this.enqueue(
          async () => {
            const wasText = this.state.selection.mode === "text";
            await this.cancelNow();
            if (wasText)
              this.state = await this.client.execute({
                operation: "selectPptx",
                revision: this.state.revision,
                ...this.state.selection,
                mode: "object",
                anchor: 0,
                focus: 0,
              });
            await this.present();
          },
          true,
          true,
        ),
      );
      return;
    }
    if (event.defaultPrevented || !this.available) return;
    if (
      (event.ctrlKey || event.metaKey) &&
      event.key.toLowerCase() === "a" &&
      this.state.selection.mode === "text"
    ) {
      event.preventDefault();
      const object = this.state.objects.find(
        (object) => object.id === this.state.selection.object,
      );
      if (object)
        this.handle(() =>
          this.select(object.id, "text", 0, object.text.length),
        );
      return;
    }
    if (this.state.selection.mode !== "object") return;
    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "z") {
      event.preventDefault();
      this.handle(() => (event.shiftKey ? this.redo() : this.undo()));
      return;
    }
    if (event.key === "Tab") {
      event.preventDefault();
      this.handle(() =>
        this.enqueue(async () =>
          this.changed(
            await this.client.execute({
              operation: "navigatePptx",
              revision: this.state.revision,
              layoutId: this.layout.id,
              direction: event.shiftKey ? "previous" : "next",
              extend: false,
            }),
          ),
        ),
      );
    } else if (event.key === "Enter") {
      event.preventDefault();
      this.handle(() => this.select(this.state.selection.object, "text"));
    } else if (
      ["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"].includes(event.key)
    ) {
      event.preventDefault();
      const step = event.shiftKey ? 10 : 1;
      const dx =
          event.key === "ArrowLeft"
            ? -step
            : event.key === "ArrowRight"
              ? step
              : 0,
        dy =
          event.key === "ArrowUp"
            ? -step
            : event.key === "ArrowDown"
              ? step
              : 0;
      this.handle(() => this.transform(dx, dy));
    } else if (event.key === "Delete" || event.key === "Backspace")
      event.preventDefault();
  };
  dispose(): Promise<void> {
    if (this.cleanup) return this.cleanup;
    this.closing = true;
    this.listeners.abort();
    cancelAnimationFrame(this.frame);
    this.pointer.reset();
    this.observable.close();
    this.cleanup = (async () => {
      try {
        await this.tail;
        await this.cancelNow();
      } finally {
        this.closed = true;
        this.surface.dispose();
        this.drawing = undefined;
        this.geometry = undefined;
        this.container.remove();
      }
    })();
    return this.cleanup;
  }
}
